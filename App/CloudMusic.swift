import Foundation
import Support
import TdSession
import UIKit

/// The music this account keeps in Telegram, and the two ways a song gets there. Cloud Music is Saved
/// Messages and nothing else: the list is that chat's history read the way a channel's is read, and an
/// "upload" is a `sendMessage` with a local file in it — how TDLib says to put a file in the cloud at all
/// (`td_api.tl:13143` + `:340`). No second library, no second table of what is where, and after Telegram
/// has the bytes the phone's copy is deleted: a song stored twice is a song whose two copies disagree
/// about whether they are downloaded, which is the number the storage screen has to report.
@MainActor
final class CloudMusic: ObservableObject {
    /// One object for the whole app. Two surfaces each making their own meant the Download on Now Playing
    /// wrote its result — the refreshed list, the `isBusy`, the reason it refused — onto an object that no
    /// screen was looking at, so the tap did its work and showed nothing.
    static let shared = CloudMusic()

    /// What the screen shows: the account's own chat, newest first, one row per song.
    @Published private(set) var songs: [StoreTrack] = []
    /// Whether a read or an upload is running — the difference between a spinner and a button that does
    /// nothing for twenty seconds.
    @Published private(set) var isBusy = false
    /// The last thing that went wrong, in words the user can act on; `nil` means the cloud is fine or
    /// nobody has asked it for anything yet.
    @Published var failure: String?

    private let library = Library.shared
    /// Resolved once per surface that asks: `createPrivateChat` is idempotent, and a second call costs one
    /// request the app does not need to make twice.
    private var chatId: Int64?
    /// Uploads in flight, keyed by the name the file was picked under, so a second ask for the same song
    /// waits for the first instead of sending a duplicate post.
    private var uploads: [String: Task<Void, Never>] = [:]
    /// The read that will reconcile the list after the last delete update, so a burst of ten is one
    /// walk of the chat rather than ten.
    private var reconciling: Task<Void, Never>?

    /// How many pages one read asks for: a hundred messages each, so twenty is two thousand — the whole of
    /// a self-chat anybody keeps songs in. Past that the loop gives up rather than walking a chat full of
    /// screenshots for a minute, one server round trip at a time.
    private static let pageCap = 20

    /// How many empty answers in a row say the chat is exhausted. Two, because TDLib returns what it
    /// has and one empty page is worth asking about again; the clear that follows this number is the
    /// only place the app removes a cloud flag it did not see, so it needs the stronger proof.
    private static let emptyPagesForEnd = 2

    /// The session is a parameter rather than a property, the way every other Telegram call here takes it:
    /// the library outlives a sign-out, and a cloud object holding a dead session is how one screen keeps
    /// listing songs the current account cannot reach.
    init() {}

    // MARK: Reading

    /// The account's own chat, read to its end, written into the same table every other song is written
    /// into. Pages, not one page: the newest hundred messages of a Saved Messages chat are usually voice
    /// notes, screenshots and links, and a song posted last autumn is nowhere near the first of them. Each
    /// page is published as it lands, so the list grows while the read runs.
    func refresh(_ session: TelegramSession) async {
        guard let id = await ensureChat(session), let saved = session.savedMessages() else { return }
        isBusy = true
        defer { isBusy = false }
        var cursor: Int64 = 0
        var held: [String] = []
        var reachedTheEnd = false
        /// Consecutive pages that came back with nothing on them.
        var emptyPages = 0
        // Whether the chat actually answered with messages. A walk that got nothing is not a chat with
        // nothing in it — TDLib can answer with an empty page while the server is still fetching — and a
        // clear built on that would empty the screen of songs perfectly well present in Telegram.
        var sawMessages = false
        for _ in 0..<Self.pageCap {
            guard let page = try? await saved.page(chatId: id, cursor: cursor) else {
                failure = "Không đọc được Saved Messages"
                break
            }
            library.rememberCloud(page: page.tracks, chatId: id)
            held.append(contentsOf: page.tracks.map(\.uniqueId))
            sawMessages = sawMessages || !page.messages.isEmpty
            reload()
            // TDLib answers with what it has, so the first page with nothing on it is a pause in the
            // read, not the bottom of the chat. Asking again at the same cursor is the whole test: only
            // a second empty answer is proof enough to clear every flag the walk never saw — a walk that
            // took one empty page for the end un-flagged a whole cloud in 1.0.2.
            if page.messages.isEmpty {
                emptyPages += 1
                if emptyPages >= Self.emptyPagesForEnd { reachedTheEnd = true }
                continue
            }
            emptyPages = 0
            guard let oldest = page.oldestMessageId, oldest != cursor else {
                // Older messages stopped arriving while the pages themselves kept coming. That is a
                // stall, and the flags below cover only the range that was actually read.
                break
            }
            cursor = oldest
        }
        // A walk that went to the bottom may clear every flag it did not see; one that stopped partway
        // clears only above the oldest id it read, because older songs were never on a page.
        if sawMessages {
            library.store.clearCloud(newerThan: reachedTheEnd ? 0 : cursor, except: held)
        }
    }

    /// The chat, created on first use. `nil` means it could not be had, and `failure` has by then said
    /// which of the three steps said no: not signed in, `getOption("my_id")` did not answer, or
    /// `createPrivateChat` refused — the first build answered `nil` for all of them and called a signed-in
    /// phone signed out.
    private func ensureChat(_ session: TelegramSession) async -> Int64? {
        if let chatId { return chatId }
        guard session.isAuthorized, let saved = session.savedMessages() else {
            failure = "Chưa đăng nhập Telegram"
            return nil
        }
        switch await saved.chatId(userId: session.account?.id) {
        case .success(let id):
            chatId = id
            return id
        case .failure(let why):
            print("saved messages chat refused \(why)")
            failure = localized("Không mở được Saved Messages: %@", describe(why))
            return nil
        }
    }

    private func describe(_ failure: TdSavedMessages.ChatFailure) -> String {
        switch failure {
        case .noUserId(let why): return "my_id: \(why)"
        case .noChat(let why): return "createPrivateChat: \(why)"
        }
    }

    /// The rows the store says are in the chat, newest first, one per song. Read from the database rather
    /// than the library's published array: a walk writes rows without republishing them, so a screen that
    /// filters a snapshot it was never told about shows only what was already on the phone when it opened —
    /// which is how a song forwarded into Saved Messages appeared in Telegram and not here.
    func reload() {
        songs = Self.distinct(library.store.cloudTracks())
    }

    // MARK: Uploading

    /// A file the user picked, put into Telegram and then thrown away locally. The order matters: uploading
    /// first means the cloud has the song before the phone gives up its copy, so a failure in the middle
    /// leaves the listener with the file rather than with nothing.
    func upload(_ session: TelegramSession, urls: [URL]) async {
        guard !urls.isEmpty else { return }
        guard let id = await ensureChat(session), let saved = session.savedMessages() else { return }
        isBusy = true
        defer { isBusy = false }
        for url in urls {
            // The read goes through the same door the import used: a picker's URL is a promise about
            // a file, and only coordination makes the system hand over bytes that can be uploaded.
            guard let path = await CloudMusic.stage(url) else {
                failure = localized("Không mở được %@", url.lastPathComponent)
                continue
            }
            let name = url.lastPathComponent
            if let running = uploads[name] {
                await running.value
                continue
            }
            let task: Task<Void, Never> = Task { [weak self] in
                guard let self else { return }
                await self.send(saved, path: path, fileName: name, chatId: id)
            }
            uploads[name] = task
            await task.value
            uploads[name] = nil
        }
        await refresh(session)
    }

    private func send(_ saved: TdSavedMessages, path: String, fileName: String,
                      chatId: Int64) async {
        if alreadyUploaded(named: fileName, path: path) {
            print("cloud duplicate \(fileName)")
            failure = "Bài này đã ở Cloud Music rồi"
            try? FileManager.default.removeItem(atPath: path)
            return
        }
        let caption = await CloudMusic.caption(for: path, named: fileName)
        do {
            let messageId = try await saved.upload(chatId: chatId, path: path, caption: caption)
            print("cloud uploaded \(fileName) as message \(messageId)")
            // Telegram has it, and the staged copy was a temp file this app made: the phone keeps only
            // what streaming caches on its own.
            try? FileManager.default.removeItem(atPath: path)
        } catch {
            // TDLib's own words: "upload failed" is not something the person holding the phone can act on
            // or send to anybody.
            failure = localized("Tải lên thất bại: %@ — %@", fileName, "\(error)")
            print("cloud upload failed \(fileName): \(error)")
        }
    }

    /// Whether the cloud already holds this song under the name it was picked with. Asked of the rows, not
    /// of a private ledger of file hashes: a ledger the user can neither see nor clear goes on refusing an
    /// upload after they deleted the song from Telegram, and the chat's history is the one answer that says
    /// what is really there.
    private func alreadyUploaded(named fileName: String, path: String) -> Bool {
        let size = CloudMusic.size(ofPath: path)
        return library.store.cloudTracks().contains { row in
            guard row.fileName == fileName else { return false }
            // The bytes must agree too, unless one of the two sizes is missing: two songs can share a name
            // across two albums, and refusing the second loses a song nobody was told about.
            return size == 0 || row.size == 0 || row.size == size
        }
    }

    // MARK: Deleting

    /// Taking a song out of Saved Messages, and off the list.
    ///
    /// The flag goes first and the read follows: nobody should keep staring at a row whose message
    /// Telegram has already agreed to delete, and the read is what proves the rest of the list still
    /// matches the chat.
    func delete(_ session: TelegramSession, _ song: StoreTrack) async {
        guard let id = await ensureChat(session), let saved = session.savedMessages() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await saved.delete(chatId: id, messageIds: [song.messageId])
            library.store.setCloud(false, uniqueIds: [song.uniqueId])
            reload()
            await refresh(session)
        } catch {
            failure = localized("Xoá thất bại: %@ — %@", song.displayTitle, "\(error)")
        }
    }

    /// Watching for posts the account deleted somewhere else — in Telegram itself, or on a desktop.
    ///
    /// One read per burst: TDLib sends the update per message, and a listener who cleared ten songs
    /// should not pay for ten walks of the chat.
    func watchDeletes(_ session: TelegramSession) async {
        guard let stream = session.deletedMessages() else { return }
        // Resolved here rather than read from `chatId`: this task starts alongside the first refresh, and
        // updates that arrive before the chat is had are updates about songs that would stay on the list
        // until the app is reopened.
        guard let id = await ensureChat(session) else { return }
        for await update in stream {
            guard update["chat_id"]?.int == id else { continue }
            let messageIds = (update["message_ids"]?.array ?? []).compactMap { $0.int }
            // The update names the posts that are gone, which is enough to drop them now. The walk it also
            // schedules is the backstop for rows a delete update never sends.
            if !messageIds.isEmpty {
                library.store.clearCloud(messageIds: messageIds)
                reload()
            }
            reconciling?.cancel()
            reconciling = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await self?.refresh(session)
            }
        }
    }

    // MARK: What the post says

    /// The words a post about this song should carry. A document post has no title and no singer of its
    /// own — Telegram keeps only the file name and the sender's caption (`td_api.tl:594`) — so an artist's
    /// name survives the cloud only written into the caption, in the shape the music channels themselves
    /// use, `Tiêu đề:` over `Thể hiện:` (`Docs/design-tokens.md:362`), which is the shape `TdTrack` already
    /// reads back: what one half of the app writes the other half finds, and no second naming rule is born.
    /// MeloX uploads the same way, opening the container for its tags before it names a post
    /// (`CloudUploadFile.swift:48-69`).
    static func caption(title: String, artist: String, fallback: String) -> String {
        let name = title.isEmpty ? (fallback as NSString).deletingPathExtension : title
        var lines: [String] = []
        if !name.isEmpty { lines.append("Tiêu đề: \(name)") }
        if !artist.isEmpty { lines.append("Thể hiện: \(artist)") }
        return lines.isEmpty ? fallback : lines.joined(separator: "\n")
    }

    /// The caption for a file this app is about to send, out of the tags written inside it.
    private static func caption(for path: String, named fileName: String) async -> String {
        let tags = await AudioTags.read(path: path)
        return caption(title: tags.title, artist: tags.performer, fallback: fileName)
    }

    // MARK: Now Playing's Download

    /// The song under the playhead, put into Saved Messages. A streamed song is the awkward case: the phone
    /// may hold a third of it and TDLib uploads only files it has whole, so the missing bytes are fetched
    /// first at the song's own priority. That is why this says what it is doing instead of appearing to
    /// finish instantly — a Download on a long mix is a minute of network, and a silent minute is what got
    /// this app called broken.
    func publish(_ session: TelegramSession, _ track: any Playable) async -> Bool {
        guard let id = await ensureChat(session) else { return false }
        isBusy = true
        defer { isBusy = false }
        var path = track.localPath
        if path == nil || !FileManager.default.fileExists(atPath: path ?? "") {
            path = await session.covers()?.path(TdFile(audio: track),
                                                priority: TdFileDownloader.audioPriority)
        }
        guard let path, FileManager.default.fileExists(atPath: path) else {
            failure = "Không tải được file của bài này"
            return false
        }
        if library.store.isInCloud(uniqueId: track.uniqueId) {
            failure = "Bài này đã ở Cloud Music rồi"
            return false
        }
        let caption = CloudMusic.caption(title: track.displayTitle,
                                         artist: track.displayPerformer,
                                         fallback: track.fileName)
        do {
            guard let saved = session.savedMessages() else {
                failure = "Chưa đăng nhập Telegram"
                return false
            }
            let messageId = try await saved.upload(chatId: id, path: path, caption: caption)
            print("cloud published \(track.fileName) as message \(messageId)")
            await refresh(session)
            return true
        } catch {
            failure = localized("Tải lên thất bại: %@ — %@", track.fileName, "\(error)")
            return false
        }
    }

    // MARK: One row per song

    /// The list with its duplicates folded, the first of each pair kept. A song can reach the chat twice —
    /// forwarded once, uploaded once — and Telegram gives every post its own `file_unique_id`, so the
    /// store's key cannot merge them and the screen would show one record twice. "The same song" here is a
    /// name and a size; a row with no name falls back to the title and the length the app measured.
    static func distinct(_ rows: [StoreTrack]) -> [StoreTrack] {
        var seen: Set<String> = []
        var kept: [StoreTrack] = []
        for row in rows where seen.insert(Self.sameSongKey(row)).inserted {
            kept.append(row)
        }
        return kept
    }

    private static func sameSongKey(_ row: StoreTrack) -> String {
        if !row.fileName.isEmpty, row.size > 0 {
            return "f:\(row.fileName.lowercased())@\(row.size)"
        }
        if !row.title.isEmpty { return "t:\(row.title.lowercased())/\(row.duration ?? 0)" }
        return "u:\(row.uniqueId)"
    }

    // MARK: Staging

    /// A readable copy of a picked file, in the app's own temporary directory. The upload needs a path it
    /// can open long after the picker has gone away, and a security-scoped URL does not survive that. The
    /// bytes are copied rather than moved because a file the user chose is theirs to keep.
    private nonisolated static func stage(_ url: URL) async -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return await Task.detached(priority: .userInitiated) {
            let coordinator = NSFileCoordinator()
            var error: NSError?
            var result: String?
            coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &error) { readable in
                let destination = CloudMusic.stagingDirectory().appendingPathComponent(
                    String(url.lastPathComponent.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" })
                )
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: readable, to: destination)
                    result = destination.path
                } catch {
                    print("cloud stage failed \(url.lastPathComponent): \(error)")
                }
            }
            return result
        }.value
    }

    nonisolated private static func stagingDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DoniUploads",
                                                                               isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private nonisolated static func size(ofPath path: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
