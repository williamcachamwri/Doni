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

private func makeFlow() -> (FakeTransport, TdLoginFlow, RecordingKeyProvider) {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 1)
    client.start()
    let keys = RecordingKeyProvider()
    return (transport, TdLoginFlow(client: client, parameters: testParameters, keyProvider: keys), keys)
}

@Test("TDLib parameters go first, with api_id as a number")
func parametersAreSentBeforeAnythingElse() async throws {
    let (transport, flow, _) = makeFlow()
    let responder = startResponder(transport)
    defer { responder.cancel() }

    let begin = Task { try await flow.begin() }
    #expect(await polled { transport.sentRequests.count >= 1 })
    begin.cancel()

    let request = transport.decodedRequests[0]
    #expect(request.type == "setTdlibParameters")
    let parameters = request["parameters"]
    #expect(parameters?["api_id"]?.int == 12345)
    #expect(parameters?["api_hash"]?.string == "deadbeef")
    #expect(parameters?["database_directory"]?.string == "/tmp/doni/db")
    #expect(parameters?["files_directory"]?.string == "/tmp/doni/files")
    #expect(parameters?["use_message_database"]?.bool == true)
    #expect(parameters?["use_secret_chats"]?.bool == false)
    #expect(parameters?["system_language_code"]?.string == "vi")
}

@Test("The encryption key is asked for only when TDLib asks for it")
func encryptionKeyAnswersTheStateWithoutTheUI() async throws {
    let (transport, flow, keys) = makeFlow()
    let responder = startResponder(transport)
    defer { responder.cancel() }

    let begin = Task { try await flow.begin() }
    #expect(await polled { transport.sentRequests.count >= 1 })
    #expect(keys.requests == 0)

    transport.queue(stateUpdate("authorizationStateWaitEncryptionKey"))
    #expect(await polled { transport.decodedRequests.count >= 2 })
    let keyRequest = transport.decodedRequests.last
    #expect(keyRequest?.type == "checkDatabaseEncryptionKey")
    #expect(keyRequest?["encryption_key"]?.string == fakeKey)
    #expect(keys.requests == 1)
    begin.cancel()
}

@Test("States reach the screen in the order TDLib announced them")
func publishesStepsInOrder() async throws {
    let (transport, flow, _) = makeFlow()
    let responder = startResponder(transport)
    defer { responder.cancel() }

    let begin = Task { try await flow.begin() }
    #expect(await polled { transport.sentRequests.count >= 1 })
    let steps = flow.steps

    transport.queue(stateUpdate("authorizationStateWaitEncryptionKey"))
    transport.queue(stateUpdate("authorizationStateWaitPhoneNumber"))
    transport.queue(stateUpdate("authorizationStateReady"))

    var seen: [TdAuthorizationStep] = []
    for await step in steps {
        seen.append(step)
        if seen.count == 3 { break }
    }
    #expect(seen == [.waitEncryptionKey(isDatabaseEncrypted: false), .waitPhoneNumber, .ready])
    begin.cancel()
}

@Test("A view that arrives late still gets the state the loop already saw")
func snapshotKeepsTheLatestState() async throws {
    let (transport, flow, _) = makeFlow()
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
    let (transport, flow, _) = makeFlow()
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
    #expect(requests[3]["password"]?.string == "hunter2")
    #expect(requests[4]["@extra"] != nil)
}

@Test("A rejected code surfaces as an error on the call that sent it")
func rejectedCodeThrowsToTheCaller() async throws {
    let (transport, flow, _) = makeFlow()

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
    let (transport, flow, _) = makeFlow()
    let begin = Task { try await flow.begin() }
    #expect(await polled { transport.sentRequests.count >= 1 })
    let configureExtra = transport.decodedRequests[0]["@extra"]?.string ?? ""
    transport.queue(#"{"@type":"ok","@extra":"\#(configureExtra)"}"#)
    transport.queue(stateUpdate("authorizationStateWaitEncryptionKey"))

    #expect(await polled { transport.decodedRequests.count >= 2 })
    let keyExtra = transport.decodedRequests[1]["@extra"]?.string ?? ""
    transport.queue(
        #"{"@type":"error","@extra":"\#(keyExtra)","code":400,"message":"ENCRYPTION_KEY_INVALID"}"#
    )

    do {
        try await begin.value
        Issue.record("a bad key should not leave the flow running")
    } catch let failure as TdClient.Failure {
        #expect(failure == .response(code: 400, message: "ENCRYPTION_KEY_INVALID"))
    }
}
