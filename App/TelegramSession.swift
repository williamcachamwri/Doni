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

    var isAuthorized: Bool { step == .ready }

    private var client: TdClient?
    private var flow: TdLoginFlow?

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
        step = nil
        isWaiting = false
        start()
    }

    /// `then` runs only when the server accepted the number. TDLib does not always announce the
    /// code screen again afterwards — a number it is already waiting for a code on keeps the state
    /// — so the screen that asked for the number needs to know the request landed.
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
