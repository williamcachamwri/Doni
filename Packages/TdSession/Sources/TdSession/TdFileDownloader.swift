import Foundation

/// Watches TDLib's file downloads until the bytes are on the device.
///
/// `downloadFile` (`td_api.tl:15001`) answers straight away with a `file` that is still in flight,
/// and the progress arrives afterwards as `updateFile` (`td_api.tl:11596`) — which is why
/// `TdClient` copies those updates onto a stream of their own. One task reads that stream for
/// everybody here, because two consumers would take turns on the same updates.
public actor TdFileDownloader {
    private let flow: TdLoginFlow
    private var listeners: [Int: [UUID: AsyncStream<String?>.Continuation]] = [:]
    private var router: Task<Void, Never>?

    /// TDLib's priority is 1-32 and the higher wins (`td_api.tl:15001`). Cover art is a few tens
    /// of kilobytes and must never hold up the song the user pressed play on.
    public static let coverPriority = 1
    public static let audioPriority = 16

    /// A file TDLib has stopped talking about should not pin a row's placeholder forever, so the
    /// first wait is short and ends the way it always did.
    private static let patience: Duration = .seconds(20)

    /// It is not, though, the last word: a one-hour set is a hundred and forty megabytes, and on a
    /// phone's connection it outlasts any fixed wait that could be promised. So after the first
    /// patience the file is asked for itself, and only a run of answers that report the same
    /// `downloaded_size` ends the wait. Bytes that move are a download that works.
    private static let poll: Duration = .seconds(4)
    private static let stallWindow: Duration = .seconds(60)

    /// One caller's seat at one file. The stream is `.unbounded` so that an update landing while
    /// the caller is still waiting for its own response is kept rather than dropped.
    private struct Listener: Sendable {
        let fileId: Int
        let token: UUID
        let stream: AsyncStream<String?>
    }

    public init(flow: TdLoginFlow) {
        self.flow = flow
    }

    /// The local path once the file is on the device, `nil` if it never gets there — TDLib
    /// rejecting the request, giving up on the file, or the client closing under it.
    public func path(fileId: Int, priority: Int = TdFileDownloader.coverPriority) async -> String? {
        let listener = install(fileId)
        startRouter()

        let answer: TdJSON
        do {
            answer = try await flow.request(
                "downloadFile",
                [
                    "file_id": .int(Int64(fileId)),
                    "priority": .int(Int64(priority)),
                    "offset": .int(0),
                    "limit": .int(0),
                    // False, because the response is only the start of the download; the answer
                    // this method returns is the one TDLib sends through `updateFile`.
                    "synchronous": .bool(false)
                ]
            )
        } catch {
            detach(listener)
            return nil
        }
        if let path = Self.readyPath(in: answer) {
            detach(listener)
            return path
        }
        if Self.isUnavailable(answer) {
            detach(listener)
            return nil
        }

        // Silence is a give-up — but only silence. A file TDLib pauses or abandons never sends
        // the update that would end this wait, and a file that is merely slow keeps sending bytes
        // that no update carries, so the watch switches from the clock to the file's own progress.
        // A Task born inside an actor method keeps that isolation, so none of this needs a hop.
        let timer = Task {
            do {
                try await Task.sleep(for: Self.patience)
            } catch {
                return
            }
            var idle = Duration.zero
            var seen = Int64.min
            while !Task.isCancelled {
                guard let answer = try? await flow.request(
                    "getFile", ["file_id": .int(Int64(listener.fileId))]
                ) else {
                    // A file TDLib will not even answer about is not coming.
                    fail(listener)
                    return
                }
                if let path = Self.readyPath(in: answer) {
                    // The router's stream can miss the last update; the file itself cannot lie.
                    resolve(listener.fileId, with: path)
                    return
                }
                if Self.isUnavailable(answer) {
                    fail(listener)
                    return
                }
                let bytes = answer["local"]?["downloaded_size"]?.int ?? Int64.min
                if bytes > seen {
                    seen = bytes
                    idle = .zero
                } else {
                    idle += Self.poll
                }
                if idle >= Self.stallWindow {
                    fail(listener)
                    return
                }
                do {
                    try await Task.sleep(for: Self.poll)
                } catch {
                    return
                }
            }
        }
        // `AsyncStream` does not end on its own when the caller goes away, so cancellation is
        // answered by the same door the timer uses: an explicit `nil` into the listener's stream.
        let path = await withTaskCancellationHandler {
            await receive(from: listener)
        } onCancel: {
            timer.cancel()
            Task { await self.abandon(listener) }
        }
        timer.cancel()
        detach(listener)
        return path
    }

    /// Whether the file is already on the device, without asking for it.
    public func readyPath(fileId: Int) async -> String? {
        guard let answer = try? await flow.request("getFile", ["file_id": .int(Int64(fileId))])
        else { return nil }
        return Self.readyPath(in: answer)
    }

    /// Releases everyone waiting on this file and tells TDLib to stop fetching it.
    public func cancel(fileId: Int) {
        resolve(fileId, with: nil)
        listeners[fileId] = nil
        stop(fileId)
    }

    /// Asks TDLib for the download back. `only_if_pending` is false because a file that has sent a
    /// byte is exactly the one worth stopping: nobody wants it any more.
    private func stop(_ fileId: Int) {
        Task {
            _ = try? await flow.request(
                "cancelDownloadFile",
                ["file_id": .int(Int64(fileId)), "only_if_pending": .bool(false)]
            )
        }
    }

    private func install(_ fileId: Int) -> Listener {
        let (stream, continuation) = AsyncStream<String?>.makeStream(bufferingPolicy: .unbounded)
        let token = UUID()
        listeners[fileId, default: [:]][token] = continuation
        return Listener(fileId: fileId, token: token, stream: stream)
    }

    /// The first announcement for this file wins, including the ones made before the caller got
    /// here — which is why the listener is installed before the request is sent.
    private func receive(from listener: Listener) async -> String? {
        var path: String?
        for await value in listener.stream {
            path = value
            break
        }
        return path
    }

    private func fail(_ listener: Listener) {
        guard let continuation = listeners[listener.fileId]?[listener.token] else { return }
        listeners[listener.fileId]?.removeValue(forKey: listener.token)
        continuation.yield(nil)
        continuation.finish()
    }

    /// A row that scrolled away is a caller that has gone and a download nobody wants. TDLib keeps
    /// fetching until it is told otherwise, and a hundred covers at priority 1 still running after
    /// one flick of a finger is what holds up the song the user actually pressed play on — which is
    /// why the wait ends with `cancelDownloadFile` as well as with a `nil`.
    ///
    /// Only when this was the last seat at the file: a shelf card and a list row often want the same
    /// cover, and stopping the fetch under the one that is still waiting would leave it stranded.
    private func abandon(_ listener: Listener) {
        fail(listener)
        guard listeners[listener.fileId]?.isEmpty != false else { return }
        listeners[listener.fileId] = nil
        stop(listener.fileId)
    }

    private func detach(_ listener: Listener) {
        guard listeners[listener.fileId]?.removeValue(forKey: listener.token) != nil else { return }
        if listeners[listener.fileId]?.isEmpty == true { listeners[listener.fileId] = nil }
    }

    private func startRouter() {
        guard router == nil else { return }
        router = Task {
            for await file in flow.files {
                guard let raw = file["id"]?.int else { continue }
                let fileId = Int(raw)
                if let path = Self.readyPath(in: file) { resolve(fileId, with: path) }
                else if Self.isUnavailable(file) { resolve(fileId, with: nil) }
            }
            // The client closed, so nothing is going to finish these files.
            for fileId in listeners.keys { resolve(fileId, with: nil) }
            listeners.removeAll()
            router = nil
        }
    }

    private func resolve(_ fileId: Int, with path: String?) {
        guard let waiting = listeners.removeValue(forKey: fileId) else { return }
        for continuation in waiting.values {
            continuation.yield(path)
            continuation.finish()
        }
    }

    /// `localFile.path` is only non-empty once TDLib has the whole file (`td_api.tl:306`).
    private static func readyPath(in file: TdJSON) -> String? {
        guard let local = file["local"], local["is_downloading_completed"]?.bool == true,
              let path = local["path"]?.string, !path.isEmpty
        else { return nil }
        return path
    }

    /// The one thing in a `localFile` that means "this is never coming": `can_be_downloaded` is
    /// documented as "if it is possible to download or generate the file" (`td_api.tl:299`), and it
    /// says so whatever TDLib is or is not doing with it right now.
    ///
    /// `is_downloading_active` was read as this, and it is not: it means the file is being fetched
    /// *at this moment*, which a download TDLib has queued but not started is not (`td_api.tl:301`).
    /// `downloadFile` with `synchronous: false` answers "immediately, just after the download has
    /// been started" (`td_api.tl:15000`) — for a cover still waiting its turn that answer is
    /// inactive, and every one of those was being reported as a give-up. That is why the list stayed
    /// on its 40×30 minithumbnail: the tiles were not missing, they were queued.
    private static func isUnavailable(_ file: TdJSON) -> Bool {
        guard let local = file["local"] else { return false }
        return local["can_be_downloaded"]?.bool == false
            && local["is_downloading_completed"]?.bool != true
    }
}
