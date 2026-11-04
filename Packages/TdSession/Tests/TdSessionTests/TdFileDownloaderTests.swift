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
    downloadable: Bool = true,
    offset: Int = 0,
    prefix: Int = 0,
    size: Int = 4096,
    extra: String? = nil
) -> String {
    let answer = extra.map { "\"@extra\":\"\($0)\"," } ?? ""
    let text = #"""
    {"@type":"file",\#(answer)"id":\#(id),"size":\#(size),"expected_size":\#(size),\#
    "local":{"@type":"localFile","path":"\#(path)","can_be_downloaded":\#(downloadable ? "true" : "false"),\#
    "can_be_deleted":true,\#
    "is_downloading_active":\#(active ? "true" : "false"),\#
    "is_downloading_completed":\#(completed ? "true" : "false"),\#
    "download_offset":\#(offset),"downloaded_prefix_size":\#(prefix),"downloaded_size":\#(prefix)},\#
    "remote":{"@type":"remoteFile","id":"7f","unique_id":"u\#(id)","is_uploading_active":false,\#
    "is_uploading_completed":true,"uploaded_size":\#(size)}}
    """#
    // A fixture that does not parse would hang the request it answers, so it fails here instead.
    precondition(TdJSON.parse(text) != nil, "the \(id) file fixture is not JSON: \(text)")
    return text
}

/// A file on the phone whose bytes a test can name, so a slice read out of it can be checked.
private func written(_ text: String) throws -> (url: URL, bytes: [UInt8]) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("doni-part-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("song.mp3")
    let bytes = Array(text.utf8)
    try Data(bytes).write(to: url)
    return (url, bytes)
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

@Test("a file TDLib says it cannot fetch is a nil, not a row stuck on its placeholder")
func unavailableFileEndsImmediately() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 7005) }
    let extra = try await downloadExtra(of: session.transport)
    // `can_be_downloaded` false with nothing complete: the bytes are gone from the server's side.
    session.transport.queue(fileJSON(id: 7005, active: false, completed: false, path: "",
                                     downloadable: false, extra: extra))

    #expect(await waiting.value == nil)
}

@Test("a download TDLib has queued but not started is still a download")
func queuedFileKeepsWaiting() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 7013) }
    let extra = try await downloadExtra(of: session.transport)
    // The `downloadFile` answer is "immediately, just after the download has been started"
    // (`td_api.tl:15000`), and a file waiting its turn behind the hundred others the list asked for
    // is not active yet — `is_downloading_active` means *right now*, not *ever*. Reading it as a
    // give-up is what left every cover in the library on its 40 px minithumbnail.
    session.transport.queue(fileJSON(id: 7013, active: false, completed: false, path: "", extra: extra))
    session.transport.queue(updateFile(fileJSON(id: 7013, active: false, completed: true,
                                                path: "/tmp/doni/files/7013.jpg")))

    #expect(await waiting.value == "/tmp/doni/files/7013.jpg")
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

@Test("a caller that goes away stops waiting, hands the file back, and does not block it for anyone else")
func cancelledTaskReleasesItsSeat() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let abandoned = Task { await downloader.path(fileId: 7012) }
    let firstExtra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 7012, active: true, completed: false, path: "", extra: firstExtra))
    abandoned.cancel()
    #expect(await abandoned.value == nil)

    // A row that scrolled off the list is a download nobody wants, and TDLib goes on fetching it
    // until it is told otherwise: a hundred priority-1 covers still running after one flick is what
    // starves the song the user actually pressed play on.
    #expect(await polled {
        session.transport.decodedRequests.contains { $0.type == "cancelDownloadFile" }
    })
    let stop = try #require(requestFields(of: session.transport, type: "cancelDownloadFile"))
    #expect(stop["file_id"]?.int == 7012)
    #expect(stop["only_if_pending"]?.bool == false)

    // The file is still fetchable, so a row that appears later gets the same id.
    let retried = Task { await downloader.path(fileId: 7012) }
    let secondExtra = try await downloadExtra(of: session.transport, nth: 2)
    session.transport.queue(fileJSON(id: 7012, active: true, completed: false, path: "", extra: secondExtra))
    session.transport.queue(updateFile(fileJSON(id: 7012, active: false, completed: true,
                                                path: "/tmp/doni/files/7012.mp3")))
    #expect(await retried.value == "/tmp/doni/files/7012.mp3")
}

@Test("a second waiter on one file keeps TDLib fetching it when the first goes away")
func sharedFileIsNotCancelledUnderSomeoneElse() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    // A shelf card and a list row want the same cover, so one leaving must not stop the fetch the
    // other is still waiting on.
    let leaving = Task { await downloader.path(fileId: 7014) }
    let firstExtra = try await downloadExtra(of: session.transport)
    let staying = Task { await downloader.path(fileId: 7014) }
    let secondExtra = try await downloadExtra(of: session.transport, nth: 2)
    session.transport.queue(fileJSON(id: 7014, active: true, completed: false, path: "", extra: firstExtra))
    session.transport.queue(fileJSON(id: 7014, active: true, completed: false, path: "", extra: secondExtra))

    leaving.cancel()
    #expect(await leaving.value == nil)

    session.transport.queue(updateFile(fileJSON(id: 7014, active: false, completed: true,
                                                path: "/tmp/doni/files/7014.jpg")))
    #expect(await staying.value == "/tmp/doni/files/7014.jpg")
    // Checked last, once the give-up has certainly been processed: TDLib was never told to stop.
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "cancelDownloadFile" })
}

@Test("a header is read out of a file the phone already holds whole")
func partReadsAWholeFileAtItsOffset() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    let (url, bytes) = try written("0123456789abcdef")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let waiting = Task { await downloader.part(fileId: 8001, offset: 4, bytes: 6) }
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 8001, active: false, completed: true, path: url.path,
                                     size: bytes.count, extra: extra))

    let got = try #require(await waiting.value)
    #expect(Array(got) == Array(bytes[4..<10]))
    // A probe is a range, not a download: TDLib is told where to start and to stop by itself.
    let request = try #require(requestFields(of: session.transport, type: "downloadFile"))
    #expect(request["offset"]?.int == 4)
    #expect(request["limit"]?.int == 6)
    #expect(request["priority"]?.int == 1)
    #expect(request["synchronous"]?.bool == false)
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "cancelDownloadFile" })
}

@Test("a partial file is readable only inside the prefix TDLib says is ready")
func partStaysInsideTheReadyPrefix() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    // The last eight bytes are what TDLib had not fetched yet — and what the file on the phone is
    // full of: a partial download is longer than the bytes it has, and the rest is garbage.
    let (url, bytes) = try written("0123456789ABCDEFGH")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let waiting = Task { await downloader.part(fileId: 8002, offset: 0, bytes: 10) }
    let asked = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 8002, active: true, completed: false, path: "", extra: asked))
    let polledExtra = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 8002, active: true, completed: false, path: url.path,
                                     prefix: 10, size: bytes.count, extra: polledExtra))

    let got = try #require(await waiting.value)
    #expect(Array(got) == Array(bytes[0..<10]))
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "cancelDownloadFile" })
}

@Test("a file somebody is waiting on whole is never probed")
func probeYieldsToADownloadInFlight() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(fileId: 8003) }
    // TDLib keeps one offset and limit per file id, and the newest request overwrites them: a probe
    // sent now would truncate the song's own fetch and drop it to cover priority.
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 8003, active: true, completed: false, path: "", extra: extra))

    #expect(await downloader.part(fileId: 8003, offset: 0, bytes: 8) == nil)
    #expect(session.transport.decodedRequests.filter { $0.type == "downloadFile" }.count == 1)
    waiting.cancel()
}

@Test("a file gone from the server is no bytes, said quietly")
func partGivesUpWithoutCancelling() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.part(fileId: 8004, offset: 0, bytes: 8) }
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 8004, active: false, completed: false, path: "",
                                     downloadable: false, extra: extra))

    #expect(await waiting.value == nil)
    // `cancelDownloadFile` stops a whole file, and a probe that stopped one under a row the user
    // then pressed play on would leave that row waiting for bytes nobody is fetching.
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "cancelDownloadFile" })
}
