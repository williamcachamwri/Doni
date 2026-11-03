import Foundation
import Testing
@testable import TdSession

private func extra(ofFirstRequest transport: FakeTransport) async throws -> String {
    try await waitFor { transport.sentRequests.count >= 1 }
    return transport.decodedRequests.first?["@extra"]?.string ?? ""
}

@Test("A response is matched to the request that set its @extra")
func correlatesResponseWithRequest() async throws {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 7)
    client.start()
    defer { client.close() }

    async let pending = client.request("getChats", ["limit": .int(100)])
    let extra = try await extra(ofFirstRequest: transport)
    transport.queue(#"{"@type":"chats","@extra":"\#(extra)","total_count":3}"#)

    let response = try await pending
    #expect(response.type == "chats")
    #expect(response["total_count"]?.int == 3)
}

@Test("An error response is a thrown error, not an update")
func errorResponsesThrow() async throws {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 7)
    client.start()
    defer { client.close() }

    async let pending = client.request("getChat", ["chat_id": .int(0)])
    let extra = try await extra(ofFirstRequest: transport)
    transport.queue(#"{"@type":"error","@extra":"\#(extra)","code":400,"message":"CHAT_ID_INVALID"}"#)

    do {
        _ = try await pending
        Issue.record("an error response should not resolve a request")
    } catch let failure as TdClient.Failure {
        #expect(failure == .response(code: 400, message: "CHAT_ID_INVALID"))
    }
}

@Test("Messages with no @extra belong to the update stream, in arrival order")
func unmatchedMessagesBecomeOrderedUpdates() async throws {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 7)
    client.start()
    defer { client.close() }

    for id in 1...3 {
        transport.queue(#"{"@type":"updateNewMessage","sequence":\#(id)}"#)
    }

    var seen: [Int64] = []
    for await update in client.updates {
        if let value = update["sequence"]?.int { seen.append(value) }
        if seen.count == 3 { break }
    }
    #expect(seen == [1, 2, 3])
}

@Test("Closing terminates the loop and every request still waiting on it")
func closeReleasesPendingRequests() async throws {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 7)
    client.start()

    async let pending = client.request("getMe")
    _ = try await extra(ofFirstRequest: transport)
    client.close()

    do {
        _ = try await pending
        Issue.record("a closed client should not resolve a request")
    } catch let failure as TdClient.Failure {
        #expect(failure == .closed)
    }

    var consumed = 0
    for await _ in client.updates { consumed += 1 }
    // Reaching this line is the assertion: the stream finished instead of
    // staying open on a loop that kept running.
    #expect(consumed == 0)
    #expect(transport.sentRequests.contains(#"{"@type":"close"}"#))
}

@Test("Requests sent after close fail instead of hanging forever")
func requestAfterCloseThrows() async throws {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 7)
    client.start()
    client.close()

    do {
        _ = try await client.request("getMe")
        Issue.record("a closed client should not accept a request")
    } catch let failure as TdClient.Failure {
        #expect(failure == .closed)
    }
    // Only the close request itself reached the transport.
    #expect(transport.sentRequests.count == 1)
}

@Test("Synchronous requests go through execute and never into the loop")
func synchronousExecuteBypassesTheLoop() {
    let transport = FakeTransport()
    transport.syncReply = #"{"@type":"textEntities","entities":[]}"#
    let client = TdClient(transport: transport, clientId: 7)

    let response = client.execute("getTextEntities", ["text": .string("@telegram")])
    #expect(response?.type == "textEntities")
    #expect(transport.executedRequests.count == 1)
    #expect(transport.sentRequests.isEmpty)
}

@Test("A request carries its type, its fields and one @extra")
func requestEncodesFieldsWithExtra() async throws {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 7)
    client.start()
    defer { client.close() }

    await withTaskGroup(of: Void.self) { group in
        group.addTask { _ = try? await client.request("searchChatMessages", [
            "chat_id": .int(1234567890123),
            "query": .string("dieu"),
            "limit": .int(100),
            "filter": .object(["@type": .string("searchFilterMessages")]),
        ]) }
        // The reply never arrives on purpose: the request only has to be sent,
        // and closing is what releases the task waiting on it.
        #expect(await polled { transport.sentRequests.count >= 1 })
        group.cancelAll()
        client.close()
    }

    let request = transport.decodedRequests[0]
    #expect(request.type == "searchChatMessages")
    #expect(request["chat_id"]?.int == 1234567890123)
    #expect(request["query"]?.string == "dieu")
    #expect(request["filter"]?["@type"]?.string == "searchFilterMessages")
    #expect(request["@extra"]?.string?.isEmpty == false)
}

@Test("Two requests get two different @extra values")
func extrasAreUnique() async throws {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 7)
    client.start()
    defer { client.close() }

    await withTaskGroup(of: Void.self) { group in
        group.addTask { _ = try? await client.request("getMe") }
        _ = await polled { transport.sentRequests.count >= 1 }
        group.addTask { _ = try? await client.request("getChats") }
        _ = await polled { transport.sentRequests.count >= 2 }
        group.cancelAll()
        client.close()
    }

    // The close request TDLib received carries no @extra, so this counts the
    // two real requests only.
    let extras = transport.decodedRequests.compactMap { $0["@extra"]?.string }
    #expect(extras.count == 2)
    #expect(Set(extras).count == 2)
}
