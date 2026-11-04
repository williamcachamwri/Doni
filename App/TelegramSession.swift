import Foundation
import SwiftUI
import TdBridge
import TdSession

/// The four C functions behind the seam `TdSession` is tested against. The
/// conformance lives here rather than in TdBridge so that package keeps no
/// dependency on the session layer.
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
    /// Whose Telegram this is, once TDLib has said. The settings screen's account card is the only
    /// place it is shown, so it stays nil until the session is ready.
    @Published private(set) var account: TdAccount?

    var isAuthorized: Bool { step == .ready }

    private var client: TdClient?
    private var flow: TdLoginFlow?
    private var downloader: TdFileDownloader?

    /// Idempotent: SwiftUI can call this from several `.task` bodies.
    func start() {
        guard client == nil else { return }
        guard let parameters = Self.parameters() else {
            lastError = "Thiếu api_id/api_hash trong bundle — xem Config/Tdlib.xcconfig"
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
                self.step = step
                if step == .ready {
                    await readAccount(flow)
                }
                if step == .closed {
                    self.restart()
                    return
                }
            }
        }
        Task {
            do {
                try await flow.begin()
            } catch {
                lastError = Self.describe(error)
            }
        }
    }

    /// TDLib cannot reopen a client it has closed, so the logout path throws this one away and
    /// builds a fresh client + flow, which is what puts the login screen back on stage.
    private func restart() {
        client?.close()
        client = nil
        flow = nil
        downloader = nil
        CoverArtwork.shared.downloader = nil
        step = nil
        account = nil
        isWaiting = false
        start()
    }

    /// `then` runs only when the server accepted the number. TDLib does not always announce the
    /// code screen again afterwards — a number it is already waiting for a code on keeps the state
    /// — so the screen that asked for the number needs to know the request landed.
    /// The channel reads belong to the client the login already ran on, so they
    /// borrow the flow instead of opening a second TDLib instance.
    func reader() -> TdChannelReader? {
        flow.map(TdChannelReader.init(flow:))
    }

    /// One downloader per client, because the waiters it holds are per-instance: a logout closes
    /// the client and every file that was in flight with it.
    ///
    /// The artwork cache keeps a reference for the surfaces that hold no session of their own —
    /// the player's hero and the lock screen both want a cover too big for any row to have asked
    /// for, and neither can reach this object.
    func covers() -> TdFileDownloader? {
        if let downloader { return downloader }
        guard let flow else { return nil }
        let downloader = TdFileDownloader(flow: flow)
        self.downloader = downloader
        CoverArtwork.shared.downloader = downloader
        return downloader
    }

    /// One `getMe` on the way into the session: the account card needs a name, and TDLib is the only
    /// thing that has one. A failure leaves the card on its fallback rather than reporting an error
    /// the user cannot act on.
    private func readAccount(_ flow: TdLoginFlow) async {
        guard account == nil else { return }
        if let me = try? await flow.request("getMe") {
            account = TdAccount(user: me)
        }
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

    func logOut() {
        run { try await $0.logOut() }
    }

    private func run(
        _ action: @escaping @Sendable (TdLoginFlow) async throws -> Void,
        onSucceed then: (() -> Void)? = nil
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
            databaseDirectory: directory("db"),
            filesDirectory: directory("files"),
            deviceModel: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            applicationVersion: version
        )
    }

    /// TDLib's own storage, kept out of Documents so it is never shared or
    /// picked up as user content.
    private static func directory(_ name: String) -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Doni/Telegram/\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}
