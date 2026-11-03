import Foundation

/// Drives the login conversation: the states TDLib announces, and the one
/// request each user answer turns into.
///
/// The order is fixed by TDLib, not by us: `setTdlibParameters` only works in
/// `authorizationStateWaitTdlibParameters` (`td_api.tl:12170`) and it is the
/// only request the flow sends on its own — the database key is one of its
/// fields now, not a second step. Everything else waits for the user.
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

    /// Reads the database key, sends it inside `setTdlibParameters`, and then
    /// answers state updates until the client closes. Throws when the automatic
    /// step fails — TDLib rejecting a wrong key with a 401, or the key store
    /// refusing — because there is no screen that could retry it.
    public func begin() async throws {
        let key = try keyProvider.databaseEncryptionKey()
        _ = try await client.request("setTdlibParameters", parameters.setTdlibParameters(encryptionKey: key))
        for await update in client.updates {
            guard update.type == "updateAuthorizationState",
                  let state = update["authorization_state"]
            else { continue }
            let step = TdAuthorizationStep.decode(state)
            latest = step
            yield.yield(step)
        }
        yield.finish()
    }

    /// International format, e.g. `+84905000000`. Default settings: TDLib's
    /// own `phoneNumberAuthenticationSettings` would switch on flash calls and
    /// SMS retriever, neither of which this app needs (`td_api.tl:12192`).
    public func submitPhoneNumber(_ number: String) async throws {
        _ = try await client.request("setAuthenticationPhoneNumber", ["phone_number": .string(number)])
    }

    public func submitCode(_ code: String) async throws {
        _ = try await client.request("checkAuthenticationCode", ["code": .string(code)])
    }

    /// Only valid once `next_type` is set and the server timeout has passed
    /// (`td_api.tl:12212`); TDLib answers otherwise with an error, which the
    /// screen shows. The reason is required now and the user pressing the
    /// button is the only reason this app has.
    public func resendCode() async throws {
        _ = try await client.request(
            "resendAuthenticationCode",
            ["reason": .object(["@type": .string("resendCodeReasonUserRequest")])]
        )
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
