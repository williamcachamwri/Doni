import Foundation

/// One file, named both ways it can be named.
///
/// `fileId` is TDLib's row number in the database it happened to be using when it handed the number
/// out (`td_api.tl:326`); `uniqueId` is MTProto's name for the bytes themselves and is the same in
/// every database on every device. This app keeps its library in its own SQLite file, which outlives
/// TDLib's database by however many times that one is rebuilt — and a row number kept across a
/// rebuild is a number that now answers with a different file's bytes. That is how one song ends up
/// wearing another song's cover, permanently: the wrong bytes are filed under the right song's name.
///
/// So a `uniqueId` is asked for first and the number is only ever used to reach the bytes it has
/// been confirmed against. A caller that knows no identity says so, and gets the behaviour the
/// number alone ever had.
public struct TdFile: Sendable, Hashable {
    /// The message that can give a stale row number back its current file.
    public struct Message: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case audio
            case cover
        }

        public let chatId: Int64
        public let messageId: Int64
        public let trackUniqueId: String
        public let kind: Kind

        public init(chatId: Int64, messageId: Int64, trackUniqueId: String, kind: Kind) {
            self.chatId = chatId
            self.messageId = messageId
            self.trackUniqueId = trackUniqueId
            self.kind = kind
        }
    }

    public let fileId: Int
    public let uniqueId: String?
    public let message: Message?

    public init(fileId: Int, uniqueId: String?, message: Message? = nil) {
        self.fileId = fileId
        self.uniqueId = uniqueId
        self.message = message
    }

    var cacheKey: String? {
        if let uniqueId, !uniqueId.isEmpty { return uniqueId }
        guard message?.kind == .cover, let trackId = message?.trackUniqueId, !trackId.isEmpty
        else { return nil }
        return "gen:\(trackId)"
    }
}

/// Watches TDLib's file downloads until the bytes are on the device.
///
/// `downloadFile` (`td_api.tl:15001`) answers straight away with a `file` that is still in flight,
/// and the progress arrives afterwards as `updateFile` (`td_api.tl:11596`) — which is why
/// `TdClient` copies those updates onto a stream of their own. One task reads that stream for
/// everybody here, because two consumers would take turns on the same updates.
public actor TdFileDownloader {
    private struct Waiting: Sendable {
        let uniqueId: String?
        let continuation: AsyncStream<String?>.Continuation
    }

    private let flow: TdLoginFlow
    private var listeners: [Int: [UUID: Waiting]] = [:]
    private var router: Task<Void, Never>?

    /// Row numbers confirmed during this TDLib process, keyed by durable file identity.
    private var rows: [String: Int] = [:]

    /// TDLib's priority is 1-32 and the higher wins (`td_api.tl:15001`). Cover art is a few tens
    /// of kilobytes and must never hold up the song the user pressed play on.
    public static let coverPriority = 1
    public static let audioPriority = 16

    /// A file TDLib has stopped talking about should not pin a row's placeholder forever, so the
    /// first wait is short and ends the way it always did.
    private static let patience: Duration = .seconds(20)

    /// A probe asks for the least of anything this actor will fetch, so it shares the cover's rung.
    private static let probePoll: Duration = .milliseconds(400)
    private static let probePatience: Duration = .seconds(15)

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

    /// The row number TDLib uses for these bytes right now. `getFile` proves a stored number;
    /// when it belongs to another file, `getMessage` supplies the number this song has today.
    private func row(of file: TdFile) async -> Int? {
        if let key = file.cacheKey, let known = rows[key] { return known }
        if let wanted = file.uniqueId, !wanted.isEmpty {
            if file.fileId != 0,
               let answer = try? await flow.request(
                   "getFile", ["file_id": .int(Int64(file.fileId))]
               ),
               answer["id"]?.int == Int64(file.fileId), Self.identity(of: answer) == wanted {
                rows[wanted] = file.fileId
                return file.fileId
            }
        } else if file.message == nil {
            return file.fileId
        }

        guard let message = file.message,
              let answer = try? await flow.request(
                  "getMessage",
                  ["chat_id": .int(message.chatId), "message_id": .int(message.messageId)]
              ),
              let track = TdTrack(message: answer), track.uniqueId == message.trackUniqueId
        else { return nil }
        let fileId: Int?
        let uniqueId: String?
        switch message.kind {
        case .audio:
            fileId = track.fileId
            uniqueId = track.uniqueId
        case .cover:
            if let wanted = file.uniqueId, !wanted.isEmpty {
                fileId = Self.cover(in: answer, matching: wanted)
                uniqueId = wanted
            } else {
                fileId = track.coverFileId
                uniqueId = track.coverUniqueId
            }
        }
        guard let fileId, fileId != 0 else { return nil }
        if let wanted = file.uniqueId, !wanted.isEmpty, uniqueId != wanted { return nil }
        if let key = file.cacheKey { rows[key] = fileId }
        return fileId
    }

    private static func cover(in message: TdJSON, matching uniqueId: String) -> Int? {
        let audio = message["content"]?["audio"]
        var candidates: [TdJSON] = []
        if let thumbnail = audio?["album_cover_thumbnail"] { candidates.append(thumbnail) }
        candidates.append(contentsOf: audio?["external_album_covers"]?.array ?? [])
        for candidate in candidates {
            guard let file = candidate["file"], identity(of: file) == uniqueId,
                  let raw = file["id"]?.int else { continue }
            return Int(raw)
        }
        return nil
    }

    /// The bytes a `file` object says it holds.
    ///
    /// `fileRemoteUnknown` carries no `unique_id` at all, and that is answered as no identity rather
    /// than as an empty one: a file TDLib cannot name is a file it cannot vouch for.
    private static func identity(of file: TdJSON) -> String? {
        guard let unique = file["remote"]?["unique_id"]?.string, !unique.isEmpty else { return nil }
        return unique
    }

    private static func matches(_ file: TdJSON, uniqueId: String?) -> Bool {
        guard let uniqueId, !uniqueId.isEmpty else { return true }
        return identity(of: file) == uniqueId
    }

    /// The local path once the file is on the device, `nil` if it never gets there — TDLib
    /// rejecting the request, giving up on the file, the client closing under it, or the bytes not
    /// being the ones the caller named.
    public func path(_ file: TdFile, priority: Int = TdFileDownloader.coverPriority) async -> String? {
        guard let fileId = await row(of: file) else { return nil }
        let listener = install(fileId, uniqueId: file.uniqueId)
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
        guard answer["id"]?.int == Int64(fileId), Self.matches(answer, uniqueId: file.uniqueId)
        else {
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
                guard answer["id"]?.int == Int64(listener.fileId),
                      Self.matches(answer, uniqueId: file.uniqueId) else {
                    fail(listener)
                    return
                }
                if Self.readyPath(in: answer) != nil || Self.isUnavailable(answer) {
                    // The router's stream can miss the last update; the file itself cannot lie.
                    announce(answer)
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
    public func readyPath(_ file: TdFile) async -> String? {
        guard let fileId = await row(of: file) else { return nil }
        guard let answer = try? await flow.request("getFile", ["file_id": .int(Int64(fileId))]),
              answer["id"]?.int == Int64(fileId), Self.matches(answer, uniqueId: file.uniqueId)
        else { return nil }
        return Self.readyPath(in: answer)
    }

    /// Tells TDLib to throw its own copy of a file away.
    ///
    /// This is the only way to empty TDLib's directory that leaves TDLib knowing it has been emptied:
    /// `deleteFile` (`td_api.tl:15052`) marks the file's row in TDLib's own database as gone, so a
    /// later `downloadFile` fetches it again. Deleting the bytes from under a running TDLib instead
    /// leaves it holding a path that no longer exists, and it goes on answering `downloadFile` with
    /// that path — the song would look downloaded forever and never play.
    ///
    /// Offline, TDLib says `Ok` and does nothing until the next connection
    /// (`td_api.tl:15045-15052`), which is why the caller keeps the row's own state as the truth
    /// about the phone rather than this answer.
    public func remove(_ file: TdFile) async -> Bool {
        guard let fileId = await row(of: file) else { return false }
        return (try? await flow.request("deleteFile", ["file_id": .int(Int64(fileId))])) != nil
    }

    /// A few bytes out of a file the phone does not have, and does not get.
    ///
    /// `downloadFile`'s `limit` is not a hint: it is the number of bytes after which the fetch is
    /// canceled by itself (`td_api.tl:14998`), which is what lets the app read a container header
    /// out of a song it has no intention of downloading. The answer is whatever is readable at the
    /// offset, which may be fewer bytes than were asked for — a caller that wants a header can
    /// usually work with the beginning of one.
    ///
    /// The state is read back from `getFile` rather than from the request's own reply, because a
    /// download that ended on its limit is not one that "succeeded", and because the window that is
    /// actually readable is only ever in `download_offset` and `downloaded_prefix_size`
    /// (`td_api.tl:303-304`): the partial file on disk is longer than the bytes TDLib has, and the
    /// rest of it is garbage (`:305`).
    ///
    /// Nothing here calls `cancelDownloadFile`. The limit already did the cancelling, and telling
    /// TDLib to stop a file id stops the whole file — a probe that cancelled under a row the user
    /// then pressed play on would leave that row waiting for nothing.
    public func part(_ file: TdFile, offset: Int64, bytes: Int,
                     priority: Int = TdFileDownloader.coverPriority) async -> Data? {
        guard bytes > 0, offset >= 0 else { return nil }
        guard let fileId = await row(of: file) else { return nil }
        // TDLib keeps exactly one offset and limit per file id and the newest request overwrites them
        // (`FileManager.cpp:3103-3107`). A row waiting on the whole file is a song someone is about
        // to listen to, so it is not probed: the ask would truncate its fetch and drop its priority.
        guard listeners[fileId] == nil else { return nil }

        let ask: [String: TdJSON] = ["file_id": .int(Int64(fileId))]
        let wanted = file.uniqueId
        var file: TdJSON
        do {
            file = try await flow.request(
                "downloadFile",
                [
                    "file_id": .int(Int64(fileId)),
                    "priority": .int(Int64(priority)),
                    "offset": .int(offset),
                    "limit": .int(Int64(bytes)),
                    // False, so this reply is the file's state right now — a file already on the
                    // phone is answered here and costs no second round trip.
                    "synchronous": .bool(false)
                ]
            )
        } catch {
            return nil
        }
        guard file["id"]?.int == Int64(fileId), Self.matches(file, uniqueId: wanted)
        else { return nil }
        if Self.covers(file, from: offset, bytes: bytes) {
            return Self.slice(in: file, from: offset, bytes: bytes)
        }
        if Self.isUnavailable(file) { return nil }

        var waited: Duration = .zero
        while waited < Self.probePatience, !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.probePoll)
            } catch {
                return nil
            }
            waited += Self.probePoll
            guard let answer = try? await flow.request("getFile", ask),
                  answer["id"]?.int == Int64(fileId), Self.matches(answer, uniqueId: wanted)
            else { return nil }
            file = answer
            if Self.covers(file, from: offset, bytes: bytes) {
                return Self.slice(in: file, from: offset, bytes: bytes)
            }
            if Self.isUnavailable(file) { return nil }
        }
        // Out of patience, not necessarily out of use: the header may well have landed in the first
        // few kilobytes, which is as good an answer as the whole ask would have been.
        return Self.slice(in: file, from: offset, bytes: bytes)
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

    private func install(_ fileId: Int, uniqueId: String?) -> Listener {
        let (stream, continuation) = AsyncStream<String?>.makeStream(bufferingPolicy: .unbounded)
        let token = UUID()
        listeners[fileId, default: [:]][token] = Waiting(uniqueId: uniqueId, continuation: continuation)
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
        guard let waiting = listeners[listener.fileId]?[listener.token] else { return }
        listeners[listener.fileId]?.removeValue(forKey: listener.token)
        waiting.continuation.yield(nil)
        waiting.continuation.finish()
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
                announce(file)
            }
            // The client closed, so nothing is going to finish these files.
            for fileId in listeners.keys { resolve(fileId, with: nil) }
            listeners.removeAll()
            router = nil
        }
    }

    /// An update is delivered only to waiters whose durable identity it carries.
    private func announce(_ file: TdJSON) {
        guard let raw = file["id"]?.int else { return }
        let fileId = Int(raw)
        guard var waiting = listeners[fileId] else { return }
        let path = Self.readyPath(in: file)
        let unavailable = Self.isUnavailable(file)
        for (token, waiter) in waiting {
            let matches = Self.matches(file, uniqueId: waiter.uniqueId)
            guard !matches || path != nil || unavailable else { continue }
            waiter.continuation.yield(matches ? path : nil)
            waiter.continuation.finish()
            waiting.removeValue(forKey: token)
        }
        listeners[fileId] = waiting.isEmpty ? nil : waiting
    }

    private func resolve(_ fileId: Int, with path: String?) {
        guard let waiting = listeners.removeValue(forKey: fileId) else { return }
        for waiter in waiting.values {
            waiter.continuation.yield(path)
            waiter.continuation.finish()
        }
    }

    /// `localFile.path` is only non-empty once TDLib has the whole file (`td_api.tl:306`).
    private static func readyPath(in file: TdJSON) -> String? {
        guard let local = file["local"], local["is_downloading_completed"]?.bool == true,
              let path = local["path"]?.string, !path.isEmpty
        else { return nil }
        return path
    }

    /// The stretch of the file that is on the device and can be read: its path, the first byte that
    /// means what it says, and the one past the last.
    ///
    /// A completed download is readable whole. A partial one is readable from `download_offset` for
    /// `downloaded_prefix_size` bytes and nowhere else (`td_api.tl:304`).
    private static func readable(in file: TdJSON) -> (path: String, from: Int64, to: Int64)? {
        guard let local = file["local"], let path = local["path"]?.string, !path.isEmpty else {
            return nil
        }
        if local["is_downloading_completed"]?.bool == true {
            return (path, 0, file["size"]?.int ?? Int64.max)
        }
        let from = local["download_offset"]?.int ?? 0
        let prefix = local["downloaded_prefix_size"]?.int ?? 0
        guard prefix > 0 else { return nil }
        return (path, from, from + prefix)
    }

    /// Whether the whole of a request is on the device yet.
    private static func covers(_ file: TdJSON, from offset: Int64, bytes: Int) -> Bool {
        guard let window = readable(in: file) else { return false }
        return window.from <= offset && window.to >= offset + Int64(bytes)
    }

    /// The requested range, or as much of it as is there.
    private static func slice(in file: TdJSON, from offset: Int64, bytes: Int) -> Data? {
        guard let window = readable(in: file) else { return nil }
        let from = max(offset, window.from)
        let to = min(offset + Int64(bytes), window.to)
        guard to > from, to - from <= Int64(Int.max) else { return nil }
        return read(path: window.path, from: from, bytes: Int(to - from))
    }

    /// A range read straight off the file system, which is what TDLib itself recommends over
    /// `readFilePart` (`td_api.tl:14944`): the app has the directory, so the bytes do not need to
    /// come back through JSON.
    private static func read(path: String, from offset: Int64, bytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil else { return nil }
        return try? handle.read(upToCount: bytes)
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
