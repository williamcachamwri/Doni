import Foundation

/// One file, named both ways it can be named.
///
/// `fileId` is TDLib's row number in whichever database handed it out (`td_api.tl:326`) and is not
/// stable across a rebuild; `uniqueId` is MTProto's name for the bytes, the same in every database on
/// every device. A `uniqueId` is asked for first and the number only reaches bytes confirmed against it.
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

/// What TDLib says about one file's bytes at the moment it was asked.
///
/// A `localFile` may be *partly* on the device: TDLib writes each part at its own offset
/// (`FileDownloader.cpp:281`), so the path reads, and everything outside the ready parts is garbage
/// (`td_api.tl:305`) — the difference streaming has to respect.
public struct TdFileState: Sendable, Equatable {
    public let fileId: Int
    /// TDLib's own file. Empty while it has no local location yet.
    public let path: String
    /// The exact size on the server, which is the only number a content length may be built from
    /// (`td_api.tl:326`); `expected_size` is an estimate and is not used.
    public let size: Int64
    /// "The local copy is fully available" (`td_api.tl:302`) — the one honest offline answer.
    public let isComplete: Bool
    /// The single stretch `updateFile` admits to. It is a prefix of what is actually ready: the parts
    /// TDLib really holds are a bitmask, and only `readyBytes` reads it (`FileManager.cpp:1043-1058`).
    public let downloadOffset: Int64
    public let readyFromDownloadOffset: Int64
    /// "if it is possible to download or generate the file" (`td_api.tl:299`).
    public let canDownload: Bool
}

/// Watches TDLib's file downloads until the bytes are on the device.
///
/// `downloadFile` (`td_api.tl:15001`) answers straight away with a `file` still in flight and progress
/// arrives later as `updateFile` (`td_api.tl:11596`), which `TdClient` streams. One task reads that
/// stream for everybody here, because two consumers would take turns on the same updates.
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

    /// TDLib's priority is 1-32 and the higher wins (`td_api.tl:15001`); cover art must never hold up
    /// the song the user pressed play on.
    public static let coverPriority = 1
    public static let audioPriority = 16

    /// A file TDLib has stopped talking about should not pin a row's placeholder, so the first wait is short.
    private static let patience: Duration = .seconds(20)

    /// A probe asks for the least of anything this actor will fetch, so it shares the cover's rung.
    private static let probePoll: Duration = .milliseconds(400)
    private static let probePatience: Duration = .seconds(15)

    /// A megabyte of song is sixteen parts landing over tens of seconds, so the window is asked
    /// often and given long.
    public static let windowPoll: Duration = .milliseconds(300)
    public static let windowPatience: Duration = .seconds(25)

    /// Not the last word: a one-hour set is a hundred and forty megabytes and outlasts any fixed wait,
    /// so after the first patience the file is asked for itself and only a run of answers reporting the
    /// same `downloaded_size` ends it.
    private static let poll: Duration = .seconds(4)
    private static let stallWindow: Duration = .seconds(60)

    /// One caller's seat at one file; the stream is `.unbounded` so an update landing before the
    /// caller's own response is kept rather than dropped.
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

    /// The bytes a `file` object says it holds. `fileRemoteUnknown` carries no `unique_id` and is
    /// answered as no identity, not an empty one: TDLib cannot vouch for a file it cannot name.
    private static func identity(of file: TdJSON) -> String? {
        guard let unique = file["remote"]?["unique_id"]?.string, !unique.isEmpty else { return nil }
        return unique
    }

    private static func matches(_ file: TdJSON, uniqueId: String?) -> Bool {
        guard let uniqueId, !uniqueId.isEmpty else { return true }
        return identity(of: file) == uniqueId
    }

    /// The local path once the file is on the device, `nil` if it never gets there — TDLib rejecting,
    /// giving up, the client closing, or the bytes not the ones the caller named.
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
                    // False: the response is only the start; the answer comes through `updateFile`.
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

        // Silence is a give-up — but only silence: a file TDLib pauses or abandons never sends the
        // ending update, so the watch switches from the clock to the file's own progress.
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
        // `AsyncStream` does not end when the caller goes away, so cancellation enters through the
        // timer's door: an explicit `nil` into the listener's stream.
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
    /// The only way to empty TDLib's directory that leaves TDLib knowing: `deleteFile`
    /// (`td_api.tl:15052`) marks the row gone in its database so a later `downloadFile` refetches it,
    /// while deleting the bytes under a running TDLib leaves it answering `downloadFile` with a path
    /// that no longer exists — downloaded forever and never playing. Offline it says `Ok` until the
    /// next connection (`td_api.tl:15045-15052`), so the caller keeps the row's own state instead.
    public func remove(_ file: TdFile) async -> Bool {
        guard let fileId = await row(of: file) else { return false }
        return (try? await flow.request("deleteFile", ["file_id": .int(Int64(fileId))])) != nil
    }

    /// A few bytes out of a file the phone does not have, and does not get.
    ///
    /// `downloadFile`'s `limit` is not a hint: it is the number of bytes after which the fetch cancels
    /// itself (`td_api.tl:14998`), which lets a container header be read out of a song nobody intends
    /// to download; the answer is whatever is readable, possibly fewer bytes than were asked.
    ///
    /// The state is read back from `getFile`, not the reply: a download that ended on its limit did not
    /// "succeed", and the readable window is only ever `download_offset` and `downloaded_prefix_size`
    /// (`td_api.tl:303-304`) — the partial file on disk is longer and the rest is garbage (`:305`).
    /// Nothing calls `cancelDownloadFile`: the limit already cancelled, and cancelling a file id stops
    /// the whole file, which would leave a row the user then plays waiting for nothing.
    public func part(_ file: TdFile, offset: Int64, bytes: Int,
                     priority: Int = TdFileDownloader.coverPriority) async -> Data? {
        guard bytes > 0, offset >= 0 else { return nil }
        guard let fileId = await row(of: file) else { return nil }
        // TDLib keeps exactly one offset and limit per file id and the newest request overwrites them
        // (`FileManager.cpp:3103-3107`), so a row waiting on the whole file is not probed: the ask
        // would truncate its fetch and drop its priority.
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
                    // False, so this reply is the file's state right now: a file already on the
                    // phone costs no second round trip.
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
        // Out of patience, not out of use: a header in the first kilobytes is as good an answer as
        // the whole ask would have been.
        return Self.slice(in: file, from: offset, bytes: bytes)
    }

    // MARK: Ranges

    /// What is on the device for one file, asked without starting any download.
    public func state(_ file: TdFile) async -> TdFileState? {
        guard let fileId = await row(of: file),
              let answer = try? await flow.request("getFile", ["file_id": .int(Int64(fileId))]),
              answer["id"]?.int == Int64(fileId), Self.matches(answer, uniqueId: file.uniqueId)
        else { return nil }
        return Self.state(of: answer, fileId: fileId)
    }

    /// How many bytes starting at `offset` are on the device and mean what they say.
    ///
    /// `getFileDownloadedPrefixSize` (`td_api.tl:15006`) decodes TDLib's ready-part bitmask, so unlike
    /// `downloaded_prefix_size` in an `updateFile` it answers for a range in the *middle* of a file —
    /// why a seek can be served from what is already here. `nil` is not zero: TDLib did not answer, and
    /// reading anyway reads garbage (`td_api.tl:305`).
    public func readyBytes(_ file: TdFile, at offset: Int64) async -> Int64? {
        guard offset >= 0, let fileId = await row(of: file) else { return nil }
        guard let answer = try? await flow.request(
            "getFileDownloadedPrefixSize",
            ["file_id": .int(Int64(fileId)), "offset": .int(offset)]
        ) else { return nil }
        return answer["size"]?.int
    }

    /// Moves the window TDLib downloads for this file to `offset` and keeps the file's priority there.
    ///
    /// TDLib holds exactly one offset and one limit per row number and the newest ask overwrites them
    /// (`FileManager.cpp:3103-3107`), so this is a *move*: whoever streams the song owns the window and
    /// a second caller would take it away — why it is not guarded the way `part` is.
    ///
    /// `bytes` is what the caller needs, not a promise about the rest: this build answers `download`
    /// with `run_download(node, true)` (`FileManager.cpp:3111`), which sets `ignore_download_limit`
    /// (`FileManager.cpp:626-628`), so the limit decides only when the *asker* is satisfied
    /// (`FileManager.cpp:3019-3029`) and the fetch may carry on past the window on its own.
    @discardableResult
    public func ask(_ file: TdFile, window offset: Int64, bytes: Int64,
                    priority: Int = TdFileDownloader.audioPriority) async -> TdFileState? {
        guard offset >= 0, bytes >= 0, let fileId = await row(of: file) else { return nil }
        let answer: TdJSON
        do {
            answer = try await flow.request(
                "downloadFile",
                [
                    "file_id": .int(Int64(fileId)),
                    "priority": .int(Int64(priority)),
                    "offset": .int(offset),
                    "limit": .int(bytes),
                    "synchronous": .bool(false)
                ]
            )
        } catch {
            return nil
        }
        guard answer["id"]?.int == Int64(fileId), Self.matches(answer, uniqueId: file.uniqueId)
        else { return nil }
        return Self.state(of: answer, fileId: fileId)
    }

    /// The bytes at `offset`, cut off at whatever TDLib says is ready, so a read can never hand back
    /// the hole next to a part it has not fetched. Fewer bytes than asked is normal near the end of the
    /// file or mid-window; a caller needing the whole range asks again after the next `updateFile`. An
    /// empty answer is "not on the phone yet" and is waited through; `nil` is "TDLib will not fetch
    /// this", and waiting on it is a spinner that never ends.
    public func read(_ file: TdFile, at offset: Int64, upTo bytes: Int) async -> Data? {
        guard bytes > 0, offset >= 0, let state = await state(file) else { return nil }
        guard !state.path.isEmpty else { return Data() }
        // A whole file is readable to its end whatever the bitmask says, and the file's own length
        // bounds the read; `size` is only 0 when TDLib never learned it from the server.
        var ready = state.size - offset
        if state.isComplete {
            ready = state.size == 0 ? Int64.max : ready
        } else {
            guard state.canDownload else { return nil }
            guard let prefix = await readyBytes(file, at: offset) else { return nil }
            ready = prefix
            guard ready > 0 else { return Data() }
        }
        guard ready > 0 else { return nil }
        return Self.read(path: state.path, from: offset, bytes: Int(min(Int64(bytes), ready)))
    }

    /// Fetches one window and says how many bytes are readable there when it stops waiting.
    ///
    /// `downloadFile`'s `limit` does not stop the fetch for a caller: `download_impl` hands the node
    /// `run_download(node, true)` (`FileManager.cpp:3111`), which is `ignore_download_limit`
    /// (`FileManager.cpp:657-661`), so the limit only decides when the *asker* is answered
    /// (`FileManager.cpp:3019-3029`) and TDLib carries on with `upload.getFile` from its first
    /// unfetched part (`PartsManager.cpp:292-296`). Measured over a 166 MB set on a phone: the playhead
    /// window was being fetched at one hundred megabytes while the rest of the file was pulled on from
    /// ninety-seven — one link, the listener starving mid-song. So the window is followed by
    /// `cancelDownloadFile`, which stops the file without taking anything back: the parts already
    /// landed were written at their own offsets (`FileDownloader.cpp:281`) and stay, and the ready
    /// bitmask goes on counting them (`FileManager.cpp:3170-3196`). A fetch cancelled on the way back
    /// does not cancel the file — the caller that took its place wants those bytes still coming.
    /// `patience` is the caller's because the bets differ: the playhead song is worth half a minute, a
    /// guessed next song is not, and a test should not wait at all.
    public func fetch(_ file: TdFile, window offset: Int64, bytes: Int64,
                      priority: Int = TdFileDownloader.audioPriority,
                      patience: Duration = TdFileDownloader.windowPatience) async -> Int64 {
        guard let state = await ask(file, window: offset, bytes: bytes, priority: priority),
              state.canDownload else { return 0 }
        var ready: Int64 = 0
        let deadline = ContinuousClock.now.advanced(by: patience)
        while !Task.isCancelled {
            if let answer = await readyBytes(file, at: offset) {
                ready = answer
                if ready >= bytes || state.size > 0 && offset + ready >= state.size { return ready }
                // A window that moved is progress; one that never moved for the whole patience is not coming.
                if ContinuousClock.now > deadline { return ready }
            }
            try? await Task.sleep(for: Self.windowPoll)
            if Task.isCancelled { return 0 }
        }
        return 0
    }

    /// Stops TDLib fetching anything beyond what the listener has asked for.
    public func quiet(_ file: TdFile) async {
        guard let fileId = await row(of: file) else { return }
        _ = try? await flow.request(
            "cancelDownloadFile",
            ["file_id": .int(Int64(fileId)), "only_if_pending": .bool(false)]
        )
    }

    /// Releases everyone waiting on this file and tells TDLib to stop fetching it.
    public func cancel(fileId: Int) {        resolve(fileId, with: nil)
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

    /// A row that scrolled away is a caller gone and a download nobody wants, so the wait ends with
    /// `cancelDownloadFile` as well as a `nil`: a hundred covers at priority 1 still running after one
    /// flick of a finger hold up the song the user pressed play on. Only when this was the last seat at
    /// the file — stopping under a caller still waiting would leave it stranded.
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

    /// The `localFile` read out of a `file` answer (`td_api.tl:297-306`). A missing `local` is TDLib
    /// saying it has no local location at all, which is a state and not a failure.
    private static func state(of file: TdJSON, fileId: Int) -> TdFileState? {
        guard let local = file["local"], local.type == "localFile" else { return nil }
        return TdFileState(
            fileId: fileId,
            path: local["path"]?.string ?? "",
            size: file["size"]?.int ?? 0,
            isComplete: local["is_downloading_completed"]?.bool == true,
            downloadOffset: local["download_offset"]?.int ?? 0,
            readyFromDownloadOffset: local["downloaded_prefix_size"]?.int ?? 0,
            canDownload: local["can_be_downloaded"]?.bool ?? false
        )
    }

    /// `localFile.path` is only non-empty once TDLib has the whole file (`td_api.tl:306`).
    private static func readyPath(in file: TdJSON) -> String? {
        guard let local = file["local"], local["is_downloading_completed"]?.bool == true,
              let path = local["path"]?.string, !path.isEmpty
        else { return nil }
        return path
    }

    /// The stretch of the file that is on the device and can be read: its path, the first byte that
    /// means what it says, and the one past the last. A completed download reads whole; a partial one
    /// reads from `download_offset` for `downloaded_prefix_size` bytes and nowhere else (`td_api.tl:304`).
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

    /// A range read straight off the file system, which TDLib itself recommends over `readFilePart`
    /// (`td_api.tl:14944`): the app has the directory, so the bytes need not come back through JSON.
    private static func read(path: String, from offset: Int64, bytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil else { return nil }
        return try? handle.read(upToCount: bytes)
    }

    /// The one thing in a `localFile` that means "this is never coming": `can_be_downloaded` is
    /// documented as "if it is possible to download or generate the file" (`td_api.tl:299`), and says
    /// so whatever TDLib is or is not doing with the file right now.
    ///
    /// `is_downloading_active` was read as this and is not: it means being fetched *at this moment*,
    /// which a queued download is not (`td_api.tl:301`) — and `synchronous: false` answers "immediately,
    /// just after the download has been started" (`td_api.tl:15000`), so a queued cover reads inactive.
    private static func isUnavailable(_ file: TdJSON) -> Bool {
        guard let local = file["local"] else { return false }
        return local["can_be_downloaded"]?.bool == false
            && local["is_downloading_completed"]?.bool != true
    }
}
