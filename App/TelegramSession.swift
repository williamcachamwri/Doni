import Foundation
import SwiftUI
import Support
import TdBridge
import TdSession

// Only for `UIDevice`, which is how the phone names itself in Telegram's Devices list. The desktop
// answers the same question with a constant, so it needs no AppKit here.
#if os(iOS)
    import UIKit
#endif

/// The four C functions behind the seam `TdSession` is tested against; the conformance lives here rather
/// than in TdBridge so that package keeps no dependency on the session layer.
struct BridgeTransport: TdTransporting {
    func send(clientId: Int32, request: String) {
        TdTransport.send(clientId: clientId, request: request)
    }

    func receive(timeout: Double) -> String? {
        TdTransport.receive(timeout: timeout)
    }

    func execute(request: String) -> String? {
        TdTransport.execute(request: request)
    }
}

/// The app's Telegram session: one TDLib client, its receive loop and the
/// login flow on top.
@MainActor
final class TelegramSession: ObservableObject {
    @Published private(set) var step: TdAuthorizationStep?
    @Published private(set) var isWaiting = false
    @Published private(set) var lastError: String?
    /// Whose Telegram this is, once TDLib has said — the header avatar and the account card are the two
    /// places that say it out loud, so both stay empty until the session is ready.
    @Published private(set) var account: TdAccount?
    /// The account picture at 160 px rather than the ~100 px `getMe` sends inline, which the header's
    /// 28 pt circle needs to stop being blurry. Nil until the file lands; the inline thumbnail draws under
    /// it until then.
    @Published private(set) var accountPhoto: DoniImage?

    /// Whether TDLib has said anything about this phone's session yet. The app's first screen is decided
    /// by the answer and TDLib takes a few hundred ms to give it: until then a signed-in phone and one
    /// that has never been signed in look identical, so drawing the login gate anyway is the flash every
    /// launch greeted itself with. The root waits for this instead of guessing.
    @Published private(set) var hasAnswered = false

    var isAuthorized: Bool { step == .ready }

    private var client: TdClient?
    private var flow: TdLoginFlow?
    private var downloader: TdFileDownloader?

    /// Everything that has to stop when a session ends, told to the one place that sees it end.
    ///
    /// TDLib's `authorizationStateClosed` is the only notice the app gets of a logout made elsewhere —
    /// on a desktop, a revoked session, a forced password change — and only this class receives it.
    /// Without a hook here, that path closes the client, wipes TDLib's directory and the Keychain key,
    /// and leaves the player playing, the indexer writing and the library rows readable: the four
    /// reactions the sign-out button runs are not owned by the button.
    var onSessionEnded: (@MainActor () async -> Void)?

    /// Whether the interrupted sign-out has already been resumed this launch.
    private var eraseResumed = false

    /// Idempotent: the app calls this once from its root, and any screen that finds the client missing
    /// can ask again.
    func start() {
        guard client == nil else { return }
        // Once per launch; `eraseStorage` retries inside. If it still cannot delete, starting a client
        // anyway beats a canvas waiting forever on an answer that will not come, and the flag stays set.
        if UserDefaults.standard.bool(forKey: Self.eraseKey), !eraseResumed {
            // A logout killed on the way out: TDLib must not get to reopen the database the user threw
            // away, so the promise is kept before a client exists.
            eraseResumed = true
            Task {
                if await Self.eraseStorage() {
                    UserDefaults.standard.removeObject(forKey: Self.eraseKey)
                }
                start()
            }
            return
        }
        guard let parameters = Self.parameters() else {
            lastError = "Thiếu api_id/api_hash trong bundle — xem Config/Tdlib.xcconfig"
            // Nothing is going to answer, so the root has to stop waiting for one.
            hasAnswered = true
            return
        }

        let clientId = TdTransport.createClientId()
        let client = TdClient(transport: BridgeTransport(), clientId: clientId)
        client.start()
        let flow = TdLoginFlow(client: client, parameters: parameters, keyProvider: KeychainDatabaseKey())
        self.client = client
        self.flow = flow

        Task {
            for await step in flow.steps {
                hasAnswered = true
                self.step = step
                if step == .ready {
                    // An interrupted erase belongs to the previous session. Once a new one is
                    // authorized, retrying that request on the next launch would delete it.
                    UserDefaults.standard.removeObject(forKey: Self.eraseKey)
                    await readAccount(flow)
                }
                if step == .closed {
                    await self.restart()
                    return
                }
            }
        }
        Task {
            do {
                try await flow.begin()
            } catch {
                lastError = Self.describe(error)
                // Same reason: a failed begin has no state behind it, and the root is waiting on one.
                hasAnswered = true
            }
        }
    }

    /// TDLib cannot reopen a client it has closed, so the logout path throws this one away and builds a
    /// fresh client + flow, which is what puts the login screen back on stage. The erase is awaited, not
    /// fired off: a new client opens its database and files directories on the way in, and a delete still
    /// running behind it would take back the space of the session that has just started.
    private func restart() async {
        // Before anything is thrown away: a player still running holds a file inside the directory the
        // next line deletes, and a walk still running writes rows into the database being wiped.
        await onSessionEnded?()
        client?.close()
        client = nil
        flow = nil
        downloader = nil
        CoverArtwork.shared.downloader = nil
        step = nil
        account = nil
        accountPhoto = nil
        isWaiting = false
        if await Self.eraseStorage() {
            UserDefaults.standard.removeObject(forKey: Self.eraseKey)
        } else {
            // TDLib's directory is still on the phone; its Keychain key is gone, which makes what is left
            // unreadable rather than a leak. The space is real, so the flag stays for the next launch.
            lastError = "Chưa xoá được dữ liệu Telegram — Doni sẽ thử lại khi bạn mở app lần tới"
        }
        start()
    }

    /// The sign-out's report that something on the phone could not be thrown away. It lands here because
    /// this is the object the login screen reads its errors from: a promise kept later still has to be
    /// said out loud now.
    func noteCleanupPending(_ message: String) {
        lastError = message
    }

    /// Set the moment the user asks to be signed out, cleared once the deletion has actually happened.
    /// TDLib will not let its database go while it holds it open, so the real unlink waits for the client
    /// to close — and if the app is killed in that gap, this is what makes the next launch finish the job
    /// before a session can be reopened.
    private static let eraseKey = "session.eraseOnLaunch"

    /// Everything TDLib kept on the phone, thrown away once its client has said it is closed. `logOut`
    /// ends the session and leaves both directories: the database recording which files are local, and the
    /// bytes beside it. Reopened by the next login, that record is why songs downloaded before signing out
    /// were still "on the phone" — and `file_id` is TDLib's row number inside its own database
    /// (`td_api.tl:326`), so the ids a new session hands out can point at any of those files. Several
    /// hundred megabytes, so never unlink this on the main thread.
    /// `false` means the directory is still there, and the caller must leave `eraseKey` set on that answer:
    /// reporting success either way let a busy file reopen a thrown-away database on the next login. The
    /// Keychain key goes whatever happens — an unreadable leftover is a space problem, a readable one a
    /// privacy problem.
    private nonisolated static func eraseStorage() async -> Bool {
        await Task.detached(priority: .utility) {
            var erased = false
            for attempt in 0..<3 {
                // TDLib lets go of its own handles a moment after the client says it is closed, and
                // an unlink inside that window comes back with the directory still busy.
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(300)) }
                try? FileManager.default.removeItem(at: telegramDirectory)
                if !FileManager.default.fileExists(atPath: telegramDirectory.path) {
                    erased = true
                    break
                }
            }
            KeychainDatabaseKey().erase()
            return erased
        }.value
    }

    /// `then` runs only when the server accepted the number: TDLib does not always announce the code
    /// screen again afterwards — a number it is already waiting for a code on keeps its state — so the
    /// screen that asked needs to know the request landed.
    /// The channel reads borrow the flow the login already ran on instead of a second TDLib instance.
    func reader() -> TdChannelReader? {
        flow.map(TdChannelReader.init(flow:))
    }

    /// One downloader per client: the waiters it holds are per-instance, so a logout closes the client and
    /// every file in flight with it. The artwork cache keeps a reference for surfaces that hold no session
    /// of their own — the player's hero and the lock screen want a cover too big for any row to have asked
    /// for, and neither can reach this object.
    /// The chat this account keeps for itself — Cloud Music's whole library. `nil` while signing in, for
    /// the same reason `reader()` is: no flow to ask until TDLib has answered.
    func savedMessages() -> TdSavedMessages? {
        guard let flow else { return nil }
        return TdSavedMessages(flow: flow)
    }

    func covers() -> TdFileDownloader? {
        if let downloader { return downloader }
        guard let flow else { return nil }
        let downloader = TdFileDownloader(flow: flow)
        self.downloader = downloader
        CoverArtwork.shared.downloader = downloader
        return downloader
    }

    /// Every post the account's chats make while the app is open, for the live index. Nil before a flow
    /// exists; after a logout the closed client finishes the stream, so the reader ends by itself and this
    /// hands out the new session's stream instead.
    func newMessages() -> AsyncStream<TdJSON>? {
        flow?.messages
    }

    /// The posts that went away, for the library that has to forget them without being asked.
    func deletedMessages() -> AsyncStream<TdJSON>? {
        flow?.deletes
    }

    /// One `getMe` on the way in: the account card needs a name and TDLib is the only thing that has one.
    /// A failure leaves the card on its fallback rather than reporting an error the user cannot act on.
    private func readAccount(_ flow: TdLoginFlow) async {
        guard account == nil else { return }
        guard let me = try? await flow.request("getMe") else { return }
        let account = TdAccount(user: me)
        self.account = account
        await loadPhoto(account)
    }

    /// Asked for once here rather than by each surface that draws it: the header and the account card want
    /// the same file, and TDLib answers a file already on the device without a round trip, so a relaunch
    /// costs nothing.
    private func loadPhoto(_ account: TdAccount?) async {
        guard let account, let fileId = account.avatarFileId, let files = covers() else { return }
        guard let path = await files.path(TdFile(fileId: fileId, uniqueId: account.avatarUniqueId),
                                          priority: TdFileDownloader.coverPriority) else { return }
        accountPhoto = DoniImage(contentsOfFile: path)
    }

    func submitPhoneNumber(_ number: String, then: (() -> Void)? = nil) {
        run({ try await $0.submitPhoneNumber(number) }, onSucceed: then)
    }

    func submitCode(_ code: String) {
        run { try await $0.submitCode(code) }
    }

    func resendCode() {
        run { try await $0.resendCode() }
    }

    func submitPassword(_ password: String) {
        run { try await $0.submitPassword(password) }
    }

    /// Promises the deletion before asking for the logout, so nothing can leave the app between the
    /// two and take the promise with it.
    func logOut() {
        UserDefaults.standard.set(true, forKey: Self.eraseKey)
        run({ try await $0.logOut() }, onFailure: {
            // A refused logout leaves this session alive, so there is no interrupted erase to resume.
            UserDefaults.standard.removeObject(forKey: Self.eraseKey)
        })
    }

    /// The quit path, and the only reason it is not just `close()`: the process is about to run its
    /// destructors, so the receive loop has to be *out* of TDLib rather than merely told to leave.
    /// Everything else the session owns can die with the process; a thread reading freed C++ memory
    /// cannot.
    func shutdown() {
        client?.closeAndJoin()
        client = nil
        flow = nil
    }

    private func run(
        _ action: @escaping @Sendable (TdLoginFlow) async throws -> Void,
        onSucceed then: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) {
        guard let flow else { return }
        isWaiting = true
        lastError = nil
        Task {
            do {
                try await action(flow)
                if let then {
                    then()
                }
            } catch {
                onFailure?()
                lastError = Self.describe(error)
            }
            isWaiting = false
        }
    }

    /// TDLib's own message is kept: the codes are what tells a wrong code from
    /// a flood wait from a revoked session, and those need different buttons.
    private static func describe(_ error: any Error) -> String {
        if let failure = error as? TdClient.Failure { return failure.description }
        if let failure = error as? KeychainDatabaseKey.Failure { return "Keychain: \(failure)" }
        return "\(error)"
    }

    private static func parameters() -> TdParameters? {
        let info = Bundle.main.infoDictionary ?? [:]
        let apiId = Int32((info["TDLibApiId"] as? String ?? "")) ?? Int32(info["TDLibApiId"] as? Int ?? 0)
        let apiHash = (info["TDLibApiHash"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard apiId != 0, !apiHash.isEmpty else { return nil }
        let version = (info["CFBundleShortVersionString"] as? String) ?? "0"
        return TdParameters(
            apiId: apiId,
            apiHash: apiHash,
            databaseDirectory: directory(databaseDirectory),
            filesDirectory: directory(filesDirectory),
            deviceModel: Self.deviceModel,
            systemVersion: Self.systemVersion,
            applicationVersion: version
        )
    }

    /// What TDLib files under Telegram's Devices list, so it has to describe the machine the session was
    /// opened on. `UIDevice.current.model` is just "iPhone" on the phone, and "Mac" is its exact
    /// counterpart: the same amount of truth, and nothing the protocol did not already ask for.
    private static var deviceModel: String {
        #if os(iOS)
        UIDevice.current.model
        #else
        "Mac"
        #endif
    }

    private static var systemVersion: String {
        #if os(iOS)
        UIDevice.current.systemVersion
        #else
        ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    /// TDLib's own storage root, kept out of Documents so it is never shared or picked up as user content.
    /// Computing it has no side effects: `eraseStorage` checks this same path after unlinking it, and
    /// recreating it there made every deletion report failure.
    private nonisolated static var telegramDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Doni/Telegram", isDirectory: true)
    }

    /// The bytes TDLib has fetched — streamed songs and thumbed pictures. The storage screen measures this:
    /// it is the bulk of what the app costs a phone, and none of it is counted in the library's rows.
    nonisolated static var filesDirectory: URL { telegramDirectory.appendingPathComponent("files") }

    /// TDLib's database: the session itself, the chat list, and the file table that says which bytes are on
    /// the phone.
    nonisolated static var databaseDirectory: URL { telegramDirectory.appendingPathComponent("db") }

    /// One of TDLib's two areas, made if it is not there yet.
    private nonisolated static func directory(_ url: URL) -> String {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}
