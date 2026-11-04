import Foundation
import Testing
@testable import TdSession

private let fakeKey = "c2VjcmV0LWtleQ=="

private let testParameters = TdParameters(
    apiId: 12345,
    apiHash: "deadbeef",
    databaseDirectory: "/tmp/doni/db",
    filesDirectory: "/tmp/doni/files",
    deviceModel: "iPhone 16e",
    systemVersion: "26.1",
    applicationVersion: "0.1"
)

private final class RecordingKeyProvider: TdDatabaseKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var requests: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func databaseEncryptionKey() -> String {
        lock.lock()
        calls += 1
        lock.unlock()
        return fakeKey
    }
}

/// Answers every request with `ok`, the way TDLib does, so the flow can be
/// driven without a network or a session.
private func startResponder(_ transport: FakeTransport) -> Task<Void, Never> {
    Task.detached {
        var answered: Set<String> = []
        while !Task.isCancelled {
            for request in transport.decodedRequests {
                guard let extra = request["@extra"]?.string, !answered.contains(extra) else { continue }
                answered.insert(extra)
                transport.queue(#"{"@type":"ok","@extra":"\#(extra)"}"#)
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}

private func stateUpdate(_ state: String) -> String {
    #"{"@type":"updateAuthorizationState","authorization_state":{"@type":"\#(state)"}}"#
}

private func makeFlow(
    keyProvider: any TdDatabaseKeyProviding = RecordingKeyProvider()
) -> (FakeTransport, TdLoginFlow) {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 1)
    client.start()
    return (transport, TdLoginFlow(client: client, parameters: testParameters, keyProvider: keyProvider))
}

@Test("TDLib parameters go first, flat, with api_id as a number")
func parametersAreSentBeforeAnythingElse() async throws {
    let (transport, flow) = makeFlow()
    let responder = startResponder(transport)
    defer { responder.cancel() }

    let begin = Task { try await flow.begin() }
    #expect(await polled { transport.sentRequests.count >= 1 })
    begin.cancel()

    let request = transport.decodedRequests[0]
    #expect(request.type == "setTdlibParameters")
    #expect(request["api_id"]?.int == 12345)
    #expect(request["api_hash"]?.string == "deadbeef")
    #expect(request["database_directory"]?.string == "/tmp/doni/db")
    #expect(request["files_directory"]?.string == "/tmp/doni/files")
    #expect(request["use_message_database"]?.bool == true)
    #expect(request["use_secret_chats"]?.bool == false)
    #expect(request["system_language_code"]?.string == "vi")
    // The nested tdlibParameters object of TDLib 1.8.0 is gone.
    #expect(request["parameters"] == nil)
}

@Test("The database key is read before the client is configured, not after")
func encryptionKeyIsAParameter() async throws {
    let keys = RecordingKeyProvider()
    let (transport, flow) = makeFlow(keyProvider: keys)
    let responder = startResponder(transport)
    defer { responder.cancel() }

    let begin = Task { try await flow.begin() }
    #expect(await polled { transport.sentRequests.count >= 1 })
    begin.cancel()

    #expect(transport.decodedRequests.count == 1)
    #expect(transport.decodedRequests[0]["database_encryption_key"]?.string == fakeKey)
    #expect(keys.requests == 1)
}

@Test("States reach the screen in the order TDLib announced them")
func publishesStepsInOrder() async throws {
    let (transport, flow) = makeFlow()
    let responder = startResponder(transport)
    defer { responder.cancel() }

    let begin = Task { try await flow.begin() }
    #expect(await polled { transport.sentRequests.count >= 1 })
    let steps = flow.steps

    transport.queue(stateUpdate("authorizationStateWaitTdlibParameters"))
    transport.queue(stateUpdate("authorizationStateWaitPhoneNumber"))
    transport.queue(stateUpdate("authorizationStateReady"))

    var seen: [TdAuthorizationStep] = []
    for await step in steps {
        seen.append(step)
        if seen.count == 3 { break }
    }
    #expect(seen == [.waitTdlibParameters, .waitPhoneNumber, .ready])
    begin.cancel()
}

@Test("A view that arrives late still gets the state the loop already saw")
func snapshotKeepsTheLatestState() async throws {
    let (transport, flow) = makeFlow()
    let responder = startResponder(transport)
    defer { responder.cancel() }

    let begin = Task { try await flow.begin() }
    #expect(await polled { transport.sentRequests.count >= 1 })
    transport.queue(stateUpdate("authorizationStateWaitPhoneNumber"))

    var latest: TdAuthorizationStep?
    for _ in 0..<250 {
        latest = await flow.snapshot()
        if latest == .waitPhoneNumber { break }
        try? await Task.sleep(for: .milliseconds(2))
    }
    #expect(latest == .waitPhoneNumber)
    begin.cancel()
}

@Test("Each user answer becomes the documented request")
func mapsUserAnswersToRequests() async throws {
    let (transport, flow) = makeFlow()
    let responder = startResponder(transport)
    defer { responder.cancel() }

    try await flow.submitPhoneNumber("+84905000000")
    try await flow.submitCode("12345")
    try await flow.resendCode()
    try await flow.submitPassword("hunter2")
    try await flow.logOut()

    #expect(await polled { transport.decodedRequests.count >= 5 })
    let requests = transport.decodedRequests
    #expect(requests.map { $0.type ?? "" } == [
        "setAuthenticationPhoneNumber",
        "checkAuthenticationCode",
        "resendAuthenticationCode",
        "checkAuthenticationPassword",
        "logOut",
    ])
    #expect(requests[0]["phone_number"]?.string == "+84905000000")
    // Default settings: the field is omitted rather than filled in.
    #expect(requests[0]["settings"] == nil)
    #expect(requests[1]["code"]?.string == "12345")
    #expect(requests[2]["reason"]?.type == "resendCodeReasonUserRequest")
    #expect(requests[3]["password"]?.string == "hunter2")
    #expect(requests[4]["@extra"] != nil)
}

@Test("A rejected code surfaces as an error on the call that sent it")
func rejectedCodeThrowsToTheCaller() async throws {
    let (transport, flow) = makeFlow()

    async let pending = flow.submitCode("00000")
    #expect(await polled { transport.sentRequests.count >= 1 })
    let extra = transport.decodedRequests.first?["@extra"]?.string ?? ""
    transport.queue(#"{"@type":"error","@extra":"\#(extra)","code":400,"message":"AUTH_CODE_INVALID"}"#)

    do {
        try await pending
        Issue.record("an invalid code should not succeed")
    } catch let failure as TdClient.Failure {
        #expect(failure == .response(code: 400, message: "AUTH_CODE_INVALID"))
    }
}

@Test("A wrong database key stops begin with the TDLib error")
func wrongEncryptionKeyStopsTheLoop() async throws {
    let (transport, flow) = makeFlow()
    let begin = Task { try await flow.begin() }
    #expect(await polled { transport.sentRequests.count >= 1 })
    let configureExtra = transport.decodedRequests[0]["@extra"]?.string ?? ""
    transport.queue(
        #"{"@type":"error","@extra":"\#(configureExtra)","code":401,"message":"AUTH_KEY_INVALID"}"#
    )

    do {
        try await begin.value
        Issue.record("a bad key should not leave the flow running")
    } catch let failure as TdClient.Failure {
        #expect(failure == .response(code: 401, message: "AUTH_KEY_INVALID"))
    }
}

@Test("the chat list resolves the ids getChats answers into rows of every kind")
func channelsAnswersTheChannelPicker() async throws {
    let (transport, flow) = makeFlow()
    let responder = Task.detached {
        var answered: Set<String> = []
        while !Task.isCancelled {
            for request in transport.decodedRequests {
                guard let extra = request["@extra"]?.string, !answered.contains(extra)
                else { continue }
                answered.insert(extra)
                switch request.type {
                case "getChats":
                    transport.queue("""
                    {"@type":"chats","@extra":"\(extra)","total_count":3,
                     "chat_ids":[-1001,-1002,7]}
                    """)
                case "getChat":
                    transport.queue(chatAnswer(extra, request["chat_id"]?.int ?? 0))
                case "getUser":
                    transport.queue("""
                    {"@type":"user","@extra":"\(extra)","id":7,
                     "type":{"@type":"userTypeBot"}}
                    """)
                default:
                    transport.queue(#"{"@type":"ok","@extra":"\#(extra)"}"#)
                }
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
    defer { responder.cancel() }

    let list = try await TdChannelReader(flow: flow).channels(limit: 5)
    // Every kind survives, in the order of the chat list: a walk is the same request whatever the
    // chat is, and a bot that DMs audio is one of the ways songs arrive.
    #expect(list == [
        TdChannel(chatId: -1001, username: "", title: "Nhạc Remix", kind: .channel),
        TdChannel(chatId: -1002, username: "", title: "Nhóm bàn", kind: .group),
        TdChannel(chatId: 7, username: "", title: "Bot nhạc", kind: .bot)
    ])
}

/// One `chat` answer in the shape `getChat` really has (`td_api.tl:4080`): the channel, the group
/// and the private chat the test above was asked for.
private func chatAnswer(_ extra: String, _ chatId: Int64) -> String {
    switch chatId {
    case -1001:
        return """
        {"@type":"chat","@extra":"\(extra)","id":-1001,"title":"Nhạc Remix",
         "type":{"@type":"chatTypeSupergroup","supergroup_id":1,"is_channel":true}}
        """
    case -1002:
        return """
        {"@type":"chat","@extra":"\(extra)","id":-1002,"title":"Nhóm bàn",
         "type":{"@type":"chatTypeSupergroup","supergroup_id":2,"is_channel":false}}
        """
    default:
        return """
        {"@type":"chat","@extra":"\(extra)","id":7,"title":"Bot nhạc",
         "type":{"@type":"chatTypePrivate","user_id":7}}
        """
    }
}

private struct RefusingKeyProvider: TdDatabaseKeyProviding {
    struct Denied: Error {}
    func databaseEncryptionKey() throws -> String { throw Denied() }
}

@Test("A key store that refuses reaches the caller instead of stalling the loop")
func refusingKeyProviderThrowsOutOfBegin() async throws {
    let (transport, flow) = makeFlow(keyProvider: RefusingKeyProvider())

    do {
        try await flow.begin()
        Issue.record("a refused key store should not leave the flow running")
    } catch is TdClient.Failure {
        Issue.record("the key store error should not be swallowed by TDLib")
    } catch {
        #expect(error is RefusingKeyProvider.Denied)
    }
    // The key is needed to build the parameters, so nothing could be sent.
    #expect(transport.sentRequests.isEmpty)
}
