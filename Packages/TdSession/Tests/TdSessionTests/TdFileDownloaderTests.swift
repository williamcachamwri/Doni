import Foundation
import Testing
@testable import TdSession

private let testFlowParameters = TdParameters(
    apiId: 12345,
    apiHash: "deadbeef",
    databaseDirectory: "/tmp/doni/db",
    filesDirectory: "/tmp/doni/files",
    deviceModel: "iPhone 16e",
    systemVersion: "26.1",
    applicationVersion: "0.1"
)

private struct Session: Sendable {
    let transport: FakeTransport
    let client: TdClient
    let flow: TdLoginFlow
}

private func makeSession() -> Session {
    let transport = FakeTransport()
    let client = TdClient(transport: transport, clientId: 3)
    client.start()
    let key = StaticKeyProvider()
    return Session(
        transport: transport,
        client: client,
        flow: TdLoginFlow(client: client, parameters: testFlowParameters, keyProvider: key)
    )
}

private final class StaticKeyProvider: TdDatabaseKeyProviding, @unchecked Sendable {
    func databaseEncryptionKey() -> String { "c2VjcmV0LWtleQ==" }
}

/// `td_api.tl:326` + `:343` — the shape `downloadFile` answers with and the shape
/// `updateFile` wraps.
private func fileJSON(
    id: Int,
    active: Bool,
    completed: Bool,
    path: String,
    extra: String? = nil
) -> String {
    let answer = extra.map { "\"@extra\":\"\($0)\"," } ?? ""
    let text = #"""
    {"@type":"file",\#(answer)"id":\#(id),"size":4096,"expected_size":4096,\#
    "local":{"@type":"localFile","path":"\#(path)","can_be_downloaded":true,"can_be_deleted":true,\#
    "is_downloading_active":\#(active ? "true" : "false"),\#
    "is_downloading_completed":\#(completed ? "true" : "false"),\#
    "download_offset":0,"downloaded_prefix_size":0,"downloaded_size":0},\#
    "remote":{"@type":"remoteFile","id":"7f","unique_id":"u\#(id)","is_uploading_active":false,\#
    "is_uploading_completed":true,"uploaded_size":4096}}
    """#
    // A fixture that does not parse would hang the request it answers, so it fails here instead.
    precondition(TdJSON.parse(text) != nil, "the \(id) file fixture is not JSON: \(text)")
    return text
}

private func updateFile(_ body: String) -> String {
    #"{"@type":"updateFile","file":\#(body)}"#
}

/// The `@extra` TDLib gave the nth request of this type, which is what lets a reply be
/// addressed back to the caller that asked.
private func downloadExtra(
    of transport: FakeTransport,
    type: String = "downloadFile",
    nth: Int = 1
) async throws -> String {
    try await waitFor {
        transport.decodedRequests.filter { $0.type == type }.count >= nth
    }
    let request = transport.decodedRequests.filter { $0.type == type }[nth - 1]
    return request["@extra"]?.string ?? ""
}

private func requestFields(
    of transport: FakeTransport,
    type: String
) -> TdJSON? {
    transport.decodedRequests.first { $0.type == type }
}

/// Waits until the receive loop has actually taken the replies a test queued, so a later
/// `close()` cannot delete one that was still on its way.
private func drained(_ transport: FakeTransport, _ count: Int) async throws {
    try await waitFor { transport.consumedCount >= count }
}

@Test("a download is answered by the updateFile that follows the response")
func updateCompletesTheDownload() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 7001) }
    let extra = try await downloadExtra(of: session.transport)
    // The response says the file is in flight, and the first update says the same; neither is
    // the answer.
    session.transport.queue(fileJSON(id: 7001, active: true, completed: false, path: "", extra: extra))
    session.transport.queue(updateFile(fileJSON(id: 7001, active: true, completed: false, path: "")))
    session.transport.queue(updateFile(fileJSON(id: 7001, active: false, completed: true,
                                                path: "/tmp/doni/files/7001.mp3")))

    #expect(await waiting.value == "/tmp/doni/files/7001.mp3")
}

@Test("the request is a priority-1 cover fetch, never a synchronous one")
func coverDownloadIsLowPriorityAndAsync() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 7002) }
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 7002, active: false, completed: true,
                                     path: "/tmp/doni/files/7002.mp3", extra: extra))
    _ = await waiting.value

    let request = try #require(requestFields(of: session.transport, type: "downloadFile"))
    #expect(request["file_id"]?.int == 7002)
    #expect(request["priority"]?.int == 1)
    #expect(request["synchronous"]?.bool == false)
}

@Test("a song asks TDLib louder than a cover does")
func audioOutrankscovers() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task {
        await downloader.path(fileId: 7003, priority: TdFileDownloader.audioPriority)
    }
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 7003, active: false, completed: true,
                                     path: "/tmp/doni/files/7003.mp3", extra: extra))
    _ = await waiting.value

    let request = try #require(requestFields(of: session.transport, type: "downloadFile"))
    #expect(request["priority"]?.int == 16)
}

@Test("a file already on the device is answered by the response alone")
func alreadyLocalNeedsNoUpdate() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 7004) }
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 7004, active: false, completed: true,
                                     path: "/tmp/doni/files/7004.mp3", extra: extra))

    #expect(await waiting.value == "/tmp/doni/files/7004.mp3")
}

@Test("a file TDLib has given up on is a nil, not a row stuck on its placeholder")
func stalledFileEndsImmediately() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 7005) }
    let extra = try await downloadExtra(of: session.transport)
    // Neither active nor complete: paused, failed, or deleted from local storage.
    session.transport.queue(fileJSON(id: 7005, active: false, completed: false, path: "", extra: extra))

    #expect(await waiting.value == nil)
}

@Test("an updateFile that beats the response is still heard")
func updateArrivingFirstIsNotLost() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 7006) }
    let extra = try await downloadExtra(of: session.transport)
    // TDLib finished the file while the `downloadFile` reply was still on its way, and it does
    // not replay that update.
    session.transport.queue(updateFile(fileJSON(id: 7006, active: false, completed: true,
                                                path: "/tmp/doni/files/early.mp3")))
    session.transport.queue(fileJSON(id: 7006, active: true, completed: false, path: "", extra: extra))

    #expect(await waiting.value == "/tmp/doni/files/early.mp3")
}

@Test("two rows waiting on one file are both answered by one update")
func waitersShareOneCompletion() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    async let first = downloader.path(fileId: 7007)
    let firstExtra = try await downloadExtra(of: session.transport)
    async let second = downloader.path(fileId: 7007)
    let secondExtra = try await downloadExtra(of: session.transport, nth: 2)
    #expect(firstExtra != secondExtra)

    session.transport.queue(fileJSON(id: 7007, active: true, completed: false, path: "", extra: firstExtra))
    session.transport.queue(fileJSON(id: 7007, active: true, completed: false, path: "", extra: secondExtra))
    session.transport.queue(updateFile(fileJSON(id: 7007, active: false, completed: true,
                                                path: "/tmp/doni/files/7007.mp3")))

    let paths = await [first, second]
    #expect(paths == ["/tmp/doni/files/7007.mp3", "/tmp/doni/files/7007.mp3"])
}

@Test("a file already local is readable without asking for a download")
func readyPathOnlyAsks() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.readyPath(fileId: 7008) }
    let extra = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 7008, active: false, completed: true,
                                     path: "/tmp/doni/files/7008.mp3", extra: extra))

    #expect(await waiting.value == "/tmp/doni/files/7008.mp3")
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "downloadFile" })
}

@Test("a file still in the cloud has no local path to read")
func readyPathIsNilWhenNotComplete() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.readyPath(fileId: 7009) }
    let extra = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 7009, active: false, completed: false, path: "", extra: extra))

    #expect(await waiting.value == nil)
}

@Test("a download cancelled by the app is cancelled at TDLib too")
func cancelReleasesTheWaitAndStopsTheFetch() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 7010) }
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 7010, active: true, completed: false, path: "", extra: extra))

    await downloader.cancel(fileId: 7010)
    #expect(await waiting.value == nil)
    #expect(await polled {
        session.transport.decodedRequests.contains { $0.type == "cancelDownloadFile" }
    })
    let request = try #require(requestFields(of: session.transport, type: "cancelDownloadFile"))
    #expect(request["file_id"]?.int == 7010)
    #expect(request["only_if_pending"]?.bool == false)
}

@Test("a client that closes ends every download rather than hanging the caller")
func closeReleasesEveryWaiter() async throws {
    let session = makeSession()
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 7011) }
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 7011, active: true, completed: false, path: "", extra: extra))
    // Let the response land first, so the wait that closes is the one on `updateFile`.
    try await drained(session.transport, 1)
    session.client.close()

    #expect(await waiting.value == nil)
}

@Test("a caller that goes away stops waiting and does not block the file for anyone else")
func cancelledTaskReleasesItsSeat() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let abandoned = Task { await downloader.path(fileId: 7012) }
    let firstExtra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 7012, active: true, completed: false, path: "", extra: firstExtra))
    abandoned.cancel()
    #expect(await abandoned.value == nil)

    // The file is still fetchable, so a row that appears later gets the same id.
    let retried = Task { await downloader.path(fileId: 7012) }
    let secondExtra = try await downloadExtra(of: session.transport, nth: 2)
    session.transport.queue(fileJSON(id: 7012, active: true, completed: false, path: "", extra: secondExtra))
    session.transport.queue(updateFile(fileJSON(id: 7012, active: false, completed: true,
                                                path: "/tmp/doni/files/7012.mp3")))
    #expect(await retried.value == "/tmp/doni/files/7012.mp3")
}
