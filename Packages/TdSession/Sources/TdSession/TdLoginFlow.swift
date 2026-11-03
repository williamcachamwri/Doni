import Foundation

/// Drives the login conversation: the states TDLib announces, and the one
/// request each user answer turns into.
///
/// The order is fixed by TDLib, not by us: `setTdlibParameters` only works in
/// `authorizationStateWaitTdlibParameters` (`td_api.tl:4028`) and
/// `checkDatabaseEncryptionKey` only in `authorizationStateWaitEncryptionKey`
/// (`:4031`), so both are answered here as soon as the state arrives, before
/// the UI ever sees them. Everything else waits for the user.
public actor TdLoginFlow {
    private let client: TdClient
    private let parameters: TdParameters
    private let keyProvider: any TdDatabaseKeyProviding
    private let stepStream: AsyncStream<TdAuthorizationStep>
    private let yield: AsyncStream<TdAuthorizationStep>.Continuation
    private var latest: TdAuthorizationStep?

    /// Every state change, in arrival order. One consumer; the app fans out.
    nonisolated public var steps: AsyncStream<TdAuthorizationStep> { stepStream }

    public init(
        client: TdClient,
        parameters: TdParameters,
        keyProvider: any TdDatabaseKeyProviding
    ) {
        self.client = client
        self.parameters = parameters
        self.keyProvider = keyProvider
        let (stream, continuation) = AsyncStream<TdAuthorizationStep>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.stepStream = stream
        self.yield = continuation
    }

    /// The state the screen should show right now, for a view that appears
    /// after the loop already ran.
    public func snapshot() -> TdAuthorizationStep? { latest }

    /// Sends `setTdlibParameters` and then answers state updates until the
    /// client closes. Throws when TDLib rejects one of the automatic steps —
    /// a wrong database key, for instance — because there is no screen that
    /// could retry it.
    public func begin() async throws {
        _ = try await client.request("setTdlibParameters", ["parameters": parameters.json])
        for await update in client.updates {
            guard update.type == "updateAuthorizationState",
                  let state = update["authorization_state"]
            else { continue }
            let step = TdAuthorizationStep.decode(state)
            latest = step
            yield.yield(step)
            if case .waitEncryptionKey = step {
                _ = try await client.request(
                    "checkDatabaseEncryptionKey",
                    ["encryption_key": .string(keyProvider.databaseEncryptionKey())]
                )
            }
        }
        yield.finish()
    }

    /// International format, e.g. `+84905000000`. Default settings: TDLib's
    /// own `phoneNumberAuthenticationSettings` would switch on flash calls and
    /// SMS retriever, neither of which this app needs (`td_api.tl:4037`).
    public func submitPhoneNumber(_ number: String) async throws {
        _ = try await client.request("setAuthenticationPhoneNumber", ["phone_number": .string(number)])
    }

    public func submitCode(_ code: String) async throws {
        _ = try await client.request("checkAuthenticationCode", ["code": .string(code)])
    }

    /// Only valid once `next_type` is set and the server timeout has passed
    /// (`td_api.tl:4039`); TDLib answers otherwise with an error, which the
    /// screen shows.
    public func resendCode() async throws {
        _ = try await client.request("resendAuthenticationCode")
    }

    public func submitPassword(_ password: String) async throws {
        _ = try await client.request("checkAuthenticationPassword", ["password": .string(password)])
    }

    /// Drops the session. TDLib clears its own state; the app layer still has
    /// to delete the database directories and the Keychain item, because a
    /// logout that leaves the files behind is not a logout.
    public func logOut() async throws {
        _ = try await client.request("logOut")
    }
}
