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
    /// What the screen shows: the account's own chat, newest first.
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
    /// Uploads in flight, keyed by the file's own bytes rather than by its name: the same mix sent
    /// twice from two different folders is the same song, and a listener who taps twice should get
    /// one post, not two.
    private var uploads: [String: Task<Void, Never>] = [:]

    /// The session is a parameter rather than a property, the way every other Telegram call in this
    /// app takes it: the library outlives a sign-out, and a cloud object holding a dead session is
    /// how one screen keeps listing songs the current account cannot reach.
    init() {}

    // MARK: Reading

    /// The newest page of the account's own chat, written into the same table every other song is
    /// written into.
    func refresh(_ session: TelegramSession) async {
        let id = await ensureChat(session)
        guard let id, let saved = session.savedMessages() else { return }
        guard let page = try? await saved.page(chatId: id) else {
            failure = "Không đọc được Saved Messages"
            return
        }
        library.remember(page: page.tracks, chatId: id)
        await MainActor.run { self.reload() }
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

    /// The rows the store holds for this chat, in the order the store reads them.
    func reload() {
        guard let chatId else {
            songs = []
            return
        }
        songs = library.storedTracks.filter { $0.chatId == chatId }
    }

    // MARK: Uploading

    /// A file the user picked, put into Telegram and then thrown away locally.
    ///
    /// The order matters. Uploading first means the cloud has the song before the phone gives up
    /// its copy, so a failure in the middle leaves the listener with the file rather than with
    /// nothing; deleting first would leave a song that exists only in a temp directory.
    func upload(_ session: TelegramSession, urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        guard let id = await ensureChat(session), let saved = session.savedMessages() else {
            return
        }
        for url in urls {
            // The read goes through the same door the import used: a picker's URL is a promise about
            // a file, and only coordination makes the system hand over bytes that can be uploaded.
            guard let path = await CloudMusic.stage(url) else {
                failure = localized("Không mở được %@", url.lastPathComponent)
                continue
            }
            let hash = Library.fingerprint(path: path)
            if let hash, await alreadyUploaded(hash: hash, named: url.lastPathComponent) {
                print("cloud duplicate \(url.lastPathComponent)")
                continue
            }
            if let running = uploads[hash ?? url.lastPathComponent] {
                await running.value
                continue
            }
            let task: Task<Void, Never> = Task { [weak self] in
                guard let self else { return }
                await self.send(saved, path: path, caption: url.lastPathComponent,
                                chatId: id, hash: hash)
            }
            uploads[hash ?? url.lastPathComponent] = task
            await task.value
            uploads[hash ?? url.lastPathComponent] = nil
        }
        await refresh(session)
    }

    private func send(_ saved: TdSavedMessages, path: String, caption: String,
                      chatId: Int64, hash: String?) async {
        do {
            let track = try await saved.upload(chatId: chatId, path: path, caption: caption)
            print("cloud uploaded \(caption) as file \(track.fileId)")
            // Telegram has it. The staged copy is a temp file the app made, and the song now has a
            // home, so the phone keeps only what streaming caches on its own.
            try? FileManager.default.removeItem(atPath: path)
            if let hash { CloudMusic.forget(hash: hash) }
        } catch {
            failure = localized("Tải lên thất bại: %@", caption)
            print("cloud upload failed \(caption): \(error)")
        }
    }

    /// Whether these exact bytes are already in the cloud.
    ///
    /// Name and size are compared against the rows the store has for this chat, because that is the
    /// pair a listener means by "the same song" and the only pair the app is sure of: Telegram gives
    /// every post its own file id, so a second upload of one file has no id in common with the first.
    private func alreadyUploaded(hash: String, named fileName: String) async -> Bool {
        if let chatId, library.storedTracks.contains(where: {
            $0.chatId == chatId && $0.fileName == fileName
        }) { return true }
        return CloudMusic.seen(hash: hash)
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
        let hash = Library.fingerprint(path: path)
        if let hash, await alreadyUploaded(hash: hash, named: track.fileName) {
            failure = "Bài này đã ở Cloud Music rồi"
            return false
        }
        let name = "\(track.displayTitle) – \(track.displayPerformer)".trimmingCharacters(
            in: .whitespacesAndNewlines)
        do {
            guard let saved = session.savedMessages() else {
            failure = "Chưa đăng nhập Telegram"
            return false
        }
        let sent = try await saved.upload(chatId: id, path: path,
                                             caption: name.isEmpty ? track.fileName : name)
            if let hash { CloudMusic.remember(hash: hash) }
            library.ingest(sent, with: session.covers())
            await refresh(session)
            print("cloud published \(track.fileName) as file \(sent.fileId)")
            return true
        } catch {
            failure = localized("Tải lên thất bại: %@", track.fileName)
            return false
        }
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

    /// The fingerprints this app has already put in the cloud, kept because the store cannot: an
    /// uploaded song's row is named by Telegram's file id, and the local file's hash is gone the
    /// moment the staged copy is. One line per song, in the app's own preferences, holding nothing
    /// but a hash.
    nonisolated private static let seenKey = "cloud.uploaded.hashes"

    private nonisolated static func seen(hash: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: seenKey) ?? []).contains(hash)
    }

    private nonisolated static func remember(hash: String) {
        let defaults = UserDefaults.standard
        var list = defaults.stringArray(forKey: seenKey) ?? []
        guard !list.contains(hash) else { return }
        list.append(hash)
        // Two hundred songs of hashes is 12 KB; a thousand is the point at which this stops being a
        // note and starts being a database, so the oldest go.
        if list.count > 1000 { list.removeFirst(list.count - 1000) }
        defaults.set(list, forKey: seenKey)
    }

    private nonisolated static func forget(hash: String) {
        let defaults = UserDefaults.standard
        guard var list = defaults.stringArray(forKey: seenKey) else { return }
        list.removeAll { $0 == hash }
        defaults.set(list, forKey: seenKey)
    }
}
