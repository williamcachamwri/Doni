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

    /// A file TDLib has stopped talking about should not pin a row's placeholder forever: the
    /// list falls back to the gradient after this.
    private static let patience: Duration = .seconds(20)

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
        if Self.isStalled(answer) {
            detach(listener)
            return nil
        }

        // Silence is a give-up: a file TDLib pauses or abandons never sends the update that would
        // end this wait.
        let timer = Task {
            try? await Task.sleep(for: Self.patience)
            // A Task born inside an actor method keeps that isolation, so this needs no hop.
            self.fail(listener)
        }
        // `AsyncStream` does not end on its own when the caller goes away, so cancellation is
        // answered by the same door the timer uses: an explicit `nil` into the listener's stream.
        let path = await withTaskCancellationHandler {
            await receive(from: listener)
        } onCancel: {
            timer.cancel()
            Task { await self.fail(listener) }
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
                else if Self.isStalled(file) { resolve(fileId, with: nil) }
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

    /// `localFile.path` is only non-empty once TDLib has the whole file (`td_api.tl:343`).
    private static func readyPath(in file: TdJSON) -> String? {
        guard let local = file["local"], local["is_downloading_completed"]?.bool == true,
              let path = local["path"]?.string, !path.isEmpty
        else { return nil }
        return path
    }

    /// A file that is neither complete nor being downloaded has been given up on — paused, failed
    /// or already deleted locally.
    private static func isStalled(_ file: TdJSON) -> Bool {
        guard let local = file["local"] else { return false }
        return local["is_downloading_active"]?.bool == false
            && local["is_downloading_completed"]?.bool != true
    }
}
