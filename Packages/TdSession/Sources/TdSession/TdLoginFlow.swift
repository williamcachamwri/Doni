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

    /// File progress, on the client's own second stream: watching a download must not drink the
    /// authorisation states out of `updates`, which has exactly one consumer.
    nonisolated public var files: AsyncStream<TdJSON> { client.files }

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
    ///
    /// Also the request that backs out of a code entry: TDLib has no cancel-authentication
    /// request, but accepts a new number while it is waiting for a code, a password or a
    /// registration (`AuthManager.cpp:638-648`), and answers it with a fresh
    /// `authorizationStateWaitCode` for the new number.
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

    /// Everything after `authorizationStateReady` — the reads that build the
    /// library. They go through the flow because it owns the client, and the
    /// client is the only thing in the app allowed to talk to TDLib.
    public func request(_ type: String, _ fields: [String: TdJSON] = [:]) async throws -> TdJSON {
        try await client.request(type, fields)
    }
}

/// Reads the music channels once the session is ready.
///
/// Both requests here are pinned-schema names: `searchPublicChat` (`td_api.tl:12511`)
/// resolves `t.me/<username>` to a `chat` without joining it, and `getChatHistory`
/// (`td_api.tl:12758`) walks backwards from a message id, `from_message_id: 0`
/// meaning "from the newest post".
public struct TdChannelReader: Sendable {
    public static let pageSize = 100

    private let flow: TdLoginFlow

    public init(flow: TdLoginFlow) {
        self.flow = flow
    }

    public enum Failure: Error, Equatable {
        case channelNotFound(String)
        case unexpectedResponse(String)
    }

    public func channel(username: String) async throws -> TdChannel {
        let handle = Self.handle(from: username)
        guard !handle.isEmpty, handle != "t.me" else {
            throw Failure.channelNotFound(username)
        }
        let answer = try await flow.request("searchPublicChat", ["username": .string(handle)])
        guard answer.type == "chat", let chatId = answer["id"]?.int else {
            throw Failure.channelNotFound(handle)
        }
        return TdChannel(
            chatId: chatId,
            username: handle,
            title: answer["title"]?.string ?? handle
        )
    }

    /// Accepts `VNMusicRemix`, `@VNMusicRemix` and `https://t.me/VNMusicRemix`,
    /// because all three are pasted out of a browser.
    private static func handle(from username: String) -> String {
        let last = username.split(separator: "/").last.map(String.init) ?? username
        return last.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    /// One page of at most `pageSize` messages older than `cursor`; `cursor: 0`
    /// starts at the newest post.
    public func page(chatId: Int64, cursor: Int64 = 0) async throws -> TdHistoryPage {
        let answer = try await flow.request(
            "getChatHistory",
            [
                "chat_id": .int(chatId),
                "from_message_id": .int(cursor),
                "offset": .int(0),
                "limit": .int(Int64(Self.pageSize)),
                "only_local": .bool(false)
            ]
        )
        guard answer.type == "messages", let items = answer["messages"]?.array else {
            throw Failure.unexpectedResponse(answer.type ?? "no @type")
        }
        return TdHistoryPage(messages: items, totalCount: answer["total_count"]?.int.map { Int($0) })
    }

    /// What the newest page of a channel holds, which is the one honest answer available before a
    /// walk: TDLib will not say how many songs a channel has ever posted, and a promise of
    /// "12 000 bài" turned out wrong is worse than "38 bài trong 100 tin gần nhất".
    public func probe(_ channel: TdChannel) async throws -> TdChannelProbe {
        let page = try await page(chatId: channel.chatId)
        return TdChannelProbe(channel: channel, trackCount: page.trackCount,
                              messageCount: page.messages.count)
    }

    /// The channels this account is already in, newest activity first, so the ones worth indexing are
    /// at the top of the list a picker shows. `getChats` (`td_api.tl:12507`) answers with whole
    /// `chat` objects (`:4080`), and a channel is a supergroup that says it is one
    /// (`chatTypeSupergroup`, `:3893`); the handle is not in that answer, so a channel picked from
    /// here is indexed by its chat id, which is all `getChatHistory` needs.
    public func channels(limit: Int = 50) async throws -> [TdChannel] {
        let answer = try await flow.request(
            "getChats",
            [
                "chat_list": .object(["@type": .string("chatListMain")]),
                "limit": .int(Int64(limit))
            ]
        )
        guard let items = answer["chats"]?.array else { return [] }
        return items.compactMap { chat in
            guard chat["type"]?["is_channel"]?.bool == true, let chatId = chat["id"]?.int
            else { return nil }
            return TdChannel(chatId: chatId, username: "", title: chat["title"]?.string ?? "")
        }
    }
}

/// The result of reading one page of a channel before committing to all of it.
public struct TdChannelProbe: Equatable, Sendable {
    public let channel: TdChannel
    /// Audio posts among the newest `TdChannelReader.pageSize` messages.
    public let trackCount: Int
    public let messageCount: Int

    public init(channel: TdChannel, trackCount: Int, messageCount: Int) {
        self.channel = channel
        self.trackCount = trackCount
        self.messageCount = messageCount
    }
}
