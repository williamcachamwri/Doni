import Foundation
import Support
import TdSession
import UIKit

/// The music this account keeps in Telegram, and the two ways a song gets there.
///
/// Cloud Music is Saved Messages, and nothing else: the list is that chat's history, read the way a
/// channel's history is read, and an "upload" is a `sendMessage` with a local file in it, which is
/// how TDLib says to put a file in the cloud at all (`td_api.tl:13143` + `:340`). There is no second
/// library, no second table of what is where, and no local copy kept behind the user's back — after
/// Telegram has the bytes, the phone's copy is deleted and the song lives in one place.
///
/// Why that is the honest design rather than a simplification: a song stored twice is a song whose
/// two copies disagree about whether they are downloaded, and the app has already been asked to
/// report that number on the storage screen.
@MainActor
final class CloudMusic: ObservableObject {
    /// What the screen shows: the account's own chat, newest first, one row per song.
    @Published private(set) var songs: [StoreTrack] = []
    /// Whether a read or an upload is running, which is the difference between a spinner and a
    /// button that does nothing for twenty seconds.
    @Published private(set) var isBusy = false
    /// The last thing that went wrong, said in the words the user can act on. `nil` means the cloud
    /// is fine or nobody has asked it for anything yet.
    @Published var failure: String?

    private let library = Library.shared
    /// Resolved once per surface that asks: `createPrivateChat` is idempotent, and a second call
    /// costs one request the app does not need to make twice.
    private var chatId: Int64?
    /// Uploads in flight, keyed by the name the file was picked under, so a second ask for the same
    /// song waits for the first instead of sending a duplicate post.
    private var uploads: [String: Task<Void, Never>] = [:]

    /// How many pages one read asks for. A hundred messages each, so twenty is two thousand — the
    /// whole of a self-chat anybody keeps songs in. The loop gives up after that rather than walking
    /// a chat full of screenshots for a minute: one page is a server round trip, and the songs below
    /// two thousand messages are not what the screen was asked for.
    private static let pageCap = 20

    /// The session is a parameter rather than a property, the way every other Telegram call in this
    /// app takes it: the library outlives a sign-out, and a cloud object holding a dead session is
    /// how one screen keeps listing songs the current account cannot reach.
    init() {}

    // MARK: Reading

    /// The account's own chat, read to its end, written into the same table every other song is
    /// written into.
    ///
    /// Pages, not one page: the newest hundred messages of a Saved Messages chat are usually voice
    /// notes, screenshots and links, and a song posted last autumn is nowhere near the first of them.
    /// Each page is published as it lands, so the list grows while the read runs instead of waiting
    /// for the last round trip.
    func refresh(_ session: TelegramSession) async {
        guard let id = await ensureChat(session), let saved = session.savedMessages() else { return }
        isBusy = true
        defer { isBusy = false }
        var cursor: Int64 = 0
        var held: [String] = []
        var reachedTheEnd = false
        // Whether the chat actually answered with messages. A walk that got nothing at all is not a
        // chat with nothing in it — TDLib can answer with an empty page while the server is still
        // fetching — and a clear built on that would empty the screen of songs that are in Telegram
        // perfectly well.
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
            guard let oldest = page.oldestMessageId, oldest != cursor else {
                // The chat has stopped giving out older messages. Not an end — TDLib answers with
                // what it has, so a stall is a stall — and so the flags below stay as they were.
                break
            }
            cursor = oldest
            if page.isLast {
                reachedTheEnd = true
                break
            }
        }
        // Only a read that got to the oldest message may say which songs are gone. Clearing against
        // one page would call every older song deleted.
        if reachedTheEnd, sawMessages { library.store.clearCloud(except: held) }
    }

    /// The chat, created on first use. `nil` means it could not be had, and `failure` has by then
    /// said which of the three steps said no: the session is not signed in, `getOption("my_id")`
    /// did not answer, or `createPrivateChat` refused. The first build answered `nil` for all of
    /// them and the screen called a signed-in phone signed out.
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

    /// The rows the store says are in the chat, newest first, one per song.
    ///
    /// Read from the database rather than from the library's published array: a walk writes rows
    /// without republishing them, so a screen that filters a snapshot it was never told about shows
    /// only what was already on the phone when it opened. That is how a song forwarded into Saved
    /// Messages appeared in Telegram and not here.
    func reload() {
        songs = Self.distinct(library.store.cloudTracks())
    }

    // MARK: Uploading

    /// A file the user picked, put into Telegram and then thrown away locally.
    ///
    /// The order matters. Uploading first means the cloud has the song before the phone gives up
    /// its copy, so a failure in the middle leaves the listener with the file rather than with
    /// nothing; deleting first would leave a song that exists only in a temp directory.
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
            // Telegram has it. The staged copy is a temp file the app made, and the song now has a
            // home, so the phone keeps only what streaming caches on its own.
            try? FileManager.default.removeItem(atPath: path)
        } catch {
            // TDLib's own words, because "upload failed" is a sentence the person standing in front
            // of the phone cannot act on and cannot send to anybody either.
            failure = localized("Tải lên thất bại: %@ — %@", fileName, "\(error)")
            print("cloud upload failed \(fileName): \(error)")
        }
    }

    /// Whether the cloud already holds this song, under the name it was picked with.
    ///
    /// Asked of the rows rather than of a private ledger of file hashes: a list the user can neither
    /// see nor clear is a list that goes on refusing an upload after they deleted the song from
    /// Telegram, and the chat's own history is the one answer that says what is really there.
    private func alreadyUploaded(named fileName: String, path: String) -> Bool {
        let size = CloudMusic.size(ofPath: path)
        return library.store.cloudTracks().contains { row in
            guard row.fileName == fileName else { return false }
            // The bytes have to agree too, unless one of the two numbers is missing: two songs can
            // share a name across two albums, and a cloud that refuses the second is a cloud that
            // lost a song nobody was told about.
            return size == 0 || row.size == 0 || row.size == size
        }
    }

    // MARK: What the post says

    /// The words a post about this song should carry.
    ///
    /// A document post has no title and no singer of its own — Telegram keeps the file's name and
    /// whatever caption the sender typed, and nothing else (`td_api.tl:594`) — so the only way an
    /// artist's name survives a trip into the cloud is to write it into the caption. It goes in in the
    /// shape the music channels themselves use, `Tiêu đề:` over `Thể hiện:`
    /// (`Docs/design-tokens.md:362`), because that is the shape `TdTrack` already reads back out: what
    /// one half of the app writes, the other half finds, and no second naming rule is born. MeloX
    /// uploads the same way — it opens the container for its tags before it names a post
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

    /// The song under the playhead, put into Saved Messages.
    ///
    /// A streamed song is the awkward case: the phone may hold a third of it, and TDLib can only
    /// upload a file it has whole — so the missing bytes are fetched first, at the song's own
    /// priority, and only then does the upload start. That is why this says what it is doing rather
    /// than appearing to finish instantly: a Download on a long mix is a minute of network, and a
    /// silent minute is what got this app called broken before.
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

    /// The list with its duplicates folded, the first of each pair kept.
    ///
    /// A song can reach the chat twice — forwarded once and uploaded once — and Telegram gives every
    /// post its own `file_unique_id`, so the store's key cannot merge them and the screen would show
    /// one record twice. The pair a listener means by "the same song" is its name and its size; a row
    /// with no name falls back to the title and the length the app measured.
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

    /// A readable copy of a picked file, in the app's own temporary directory.
    ///
    /// The upload needs a path it can open long after the picker has gone away, and a security-scoped
    /// URL does not survive that. `Data` is copied rather than moved because a file the user chose is
    /// theirs to keep — the app must not be the thing that deletes their Downloads folder.
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
