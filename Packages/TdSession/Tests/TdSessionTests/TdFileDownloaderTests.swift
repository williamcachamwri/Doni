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
    uniqueId: String? = nil,
    extra: String? = nil
) -> String {
    let answer = extra.map { "\"@extra\":\"\($0)\"," } ?? ""
    // The bytes' own name, which a test can disagree with on purpose: TDLib's answer about a row
    // number the app kept is the one thing this layer has to be able to say is somebody else's.
    let name = uniqueId ?? "u\(id)"
    let text = #"""
    {"@type":"file",\#(answer)"id":\#(id),"size":\#(size),"expected_size":\#(size),\#
    "local":{"@type":"localFile","path":"\#(path)","can_be_downloaded":\#(downloadable ? "true" : "false"),\#
    "can_be_deleted":true,\#
    "is_downloading_active":\#(active ? "true" : "false"),\#
    "is_downloading_completed":\#(completed ? "true" : "false"),\#
    "download_offset":\#(offset),"downloaded_prefix_size":\#(prefix),"downloaded_size":\#(prefix)},\#
    "remote":{"@type":"remoteFile","id":"7f","unique_id":"\#(name)","is_uploading_active":false,\#
    "is_uploading_completed":true,"uploaded_size":\#(size)}}
    """#
    // A fixture that does not parse would hang the request it answers, so it fails here instead.
    precondition(TdJSON.parse(text) != nil, "the \(id) file fixture is not JSON: \(text)")
    return text
}

private func coverJSON(id: Int, uniqueId: String, width: Int = 320) -> String {
    let file = fileJSON(id: id, active: false, completed: false, path: "", uniqueId: uniqueId)
    return #"{"@type":"thumbnail","format":{"@type":"thumbnailFormatJpeg"},"width":\#(width),"height":320,"file":\#(file)}"#
}

private func audioMessage(
    chatId: Int64 = 44,
    messageId: Int64 = 55,
    audioId: Int,
    audioUniqueId: String,
    cover: String? = nil,
    externalCovers: [String] = [],
    extra: String
) -> String {
    let audio = fileJSON(id: audioId, active: false, completed: false, path: "",
                         uniqueId: audioUniqueId)
    let covers = "[\(externalCovers.joined(separator: ","))]"
    let text = #"""
    {"@type":"message","@extra":"\#(extra)","id":\#(messageId),"chat_id":\#(chatId),"date":1,\#
    "content":{"@type":"messageAudio","audio":{"@type":"audio","duration":120,"title":"song",\#
    "performer":"artist","file_name":"song.mp3","mime_type":"audio/mpeg",\#
    "album_cover_minithumbnail":null,"album_cover_thumbnail":\#(cover ?? "null"),\#
    "external_album_covers":\#(covers),"audio":\#(audio)},\#
    "caption":{"@type":"formattedText","text":"","entities":[]}}}
    """#
    precondition(TdJSON.parse(text) != nil, "the message fixture is not JSON: \(text)")
    return text
}

private func origin(_ kind: TdFile.Message.Kind, trackId: String = "wanted") -> TdFile.Message {
    TdFile.Message(chatId: 44, messageId: 55, trackUniqueId: trackId, kind: kind)
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

    let waiting = Task { await downloader.path(TdFile(fileId: 7001, uniqueId: nil)) }
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

    let waiting = Task { await downloader.path(TdFile(fileId: 7002, uniqueId: nil)) }
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
        await downloader.path(TdFile(fileId: 7003, uniqueId: nil), priority: TdFileDownloader.audioPriority)
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

    let waiting = Task { await downloader.path(TdFile(fileId: 7004, uniqueId: nil)) }
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

    let waiting = Task { await downloader.path(TdFile(fileId: 7005, uniqueId: nil)) }
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

    let waiting = Task { await downloader.path(TdFile(fileId: 7013, uniqueId: nil)) }
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

    let waiting = Task { await downloader.path(TdFile(fileId: 7006, uniqueId: nil)) }
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

    async let first = downloader.path(TdFile(fileId: 7007, uniqueId: nil))
    let firstExtra = try await downloadExtra(of: session.transport)
    async let second = downloader.path(TdFile(fileId: 7007, uniqueId: nil))
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

    let waiting = Task { await downloader.readyPath(TdFile(fileId: 7008, uniqueId: nil)) }
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

    let waiting = Task { await downloader.readyPath(TdFile(fileId: 7009, uniqueId: nil)) }
    let extra = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 7009, active: false, completed: false, path: "", extra: extra))

    #expect(await waiting.value == nil)
}

@Test("throwing a file away is said to TDLib, so it knows to fetch it again")
func removeAsksTDLibToDeleteItsOwnCopy() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.remove(TdFile(fileId: 7020, uniqueId: nil)) }
    let extra = try await downloadExtra(of: session.transport, type: "deleteFile")
    session.transport.queue(#"{"@type":"ok","@extra":"\#(extra)"}"#)

    #expect(await waiting.value == true)
    let request = try #require(requestFields(of: session.transport, type: "deleteFile"))
    #expect(request["file_id"]?.int == 7020)
}

@Test("a delete TDLib cannot answer is a no, not a wait that never ends")
func removeIsFalseWhenTheRequestFails() async throws {
    let session = makeSession()
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.remove(TdFile(fileId: 7021, uniqueId: nil)) }
    _ = try await downloadExtra(of: session.transport, type: "deleteFile")
    session.client.close()

    #expect(await waiting.value == false)
}

@Test("a download cancelled by the app is cancelled at TDLib too")
func cancelReleasesTheWaitAndStopsTheFetch() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(TdFile(fileId: 7010, uniqueId: nil)) }
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

    let waiting = Task { await downloader.path(TdFile(fileId: 7011, uniqueId: nil)) }
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

    let abandoned = Task { await downloader.path(TdFile(fileId: 7012, uniqueId: nil)) }
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
    let retried = Task { await downloader.path(TdFile(fileId: 7012, uniqueId: nil)) }
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
    let leaving = Task { await downloader.path(TdFile(fileId: 7014, uniqueId: nil)) }
    let firstExtra = try await downloadExtra(of: session.transport)
    let staying = Task { await downloader.path(TdFile(fileId: 7014, uniqueId: nil)) }
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

    let waiting = Task { await downloader.part(TdFile(fileId: 8001, uniqueId: nil), offset: 4, bytes: 6) }
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

    let waiting = Task { await downloader.part(TdFile(fileId: 8002, uniqueId: nil), offset: 0, bytes: 10) }
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

    let waiting = Task { await downloader.path(TdFile(fileId: 8003, uniqueId: nil)) }
    // TDLib keeps one offset and limit per file id, and the newest request overwrites them: a probe
    // sent now would truncate the song's own fetch and drop it to cover priority.
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 8003, active: true, completed: false, path: "", extra: extra))

    #expect(await downloader.part(TdFile(fileId: 8003, uniqueId: nil), offset: 0, bytes: 8) == nil)
    #expect(session.transport.decodedRequests.filter { $0.type == "downloadFile" }.count == 1)
    waiting.cancel()
}

@Test("a file gone from the server is no bytes, said quietly")
func partGivesUpWithoutCancelling() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.part(TdFile(fileId: 8004, uniqueId: nil), offset: 0, bytes: 8) }
    let extra = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 8004, active: false, completed: false, path: "",
                                     downloadable: false, extra: extra))

    #expect(await waiting.value == nil)
    // `cancelDownloadFile` stops a whole file, and a probe that stopped one under a row the user
    // then pressed play on would leave that row waiting for bytes nobody is fetching.
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "cancelDownloadFile" })
}

@Test("a row number that names other bytes is never fetched")
func staleRowNumberIsRefused() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(TdFile(fileId: 9001, uniqueId: "wanted")) }
    let extra = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 9001, active: false, completed: true,
                                     path: "/tmp/doni/files/9001.mp3",
                                     uniqueId: "someone-else", extra: extra))

    #expect(await waiting.value == nil)
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "downloadFile" })
}

@Test("a row whose identity matches is downloaded normally")
func matchingRowNumberIsDownloaded() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(TdFile(fileId: 9002, uniqueId: "u9002")) }
    let lookup = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 9002, active: false, completed: false, path: "",
                                     uniqueId: "u9002", extra: lookup))
    let ask = try await downloadExtra(of: session.transport, type: "downloadFile")
    session.transport.queue(fileJSON(id: 9002, active: false, completed: true,
                                     path: "/tmp/doni/files/9002.mp3",
                                     uniqueId: "u9002", extra: ask))

    #expect(await waiting.value == "/tmp/doni/files/9002.mp3")
    let request = try #require(requestFields(of: session.transport, type: "downloadFile"))
    #expect(request["file_id"]?.int == 9002)
}

@Test("bytes TDLib cannot name are not accepted for a named file")
func unnamedIdentityIsRefused() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.readyPath(TdFile(fileId: 9003, uniqueId: "wanted")) }
    let extra = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 9003, active: false, completed: true,
                                     path: "/tmp/doni/files/9003.mp3",
                                     uniqueId: "", extra: extra))

    #expect(await waiting.value == nil)
}

@Test("one identity is confirmed once, however many surfaces ask for the same file")
func lookupIsRemembered() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    let file = TdFile(fileId: 9004, uniqueId: "u9004")

    let first = Task { await downloader.readyPath(file) }
    for nth in 1...2 {
        let asked = try await downloadExtra(of: session.transport, type: "getFile", nth: nth)
        session.transport.queue(fileJSON(id: 9004, active: false, completed: true,
                                         path: "/tmp/doni/files/9004.mp3", uniqueId: "u9004",
                                         extra: asked))
        if nth == 2 { #expect(await first.value == "/tmp/doni/files/9004.mp3") }
    }

    let second = Task { await downloader.readyPath(file) }
    let askedAgain = try await downloadExtra(of: session.transport, type: "getFile", nth: 3)
    session.transport.queue(fileJSON(id: 9004, active: false, completed: true,
                                     path: "/tmp/doni/files/9004.mp3", uniqueId: "u9004",
                                     extra: askedAgain))
    #expect(await second.value == "/tmp/doni/files/9004.mp3")
    #expect(session.transport.decodedRequests.filter { $0.type == "getFile" }.count == 3)
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "getMessage" })
}

@Test("a probe of a file whose identity does not match reads nothing")
func partRefusesAnUnmatchedIdentity() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task {
        await downloader.part(TdFile(fileId: 9005, uniqueId: "wanted"), offset: 0, bytes: 8)
    }
    let extra = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 9005, active: false, completed: true, path: "/nope.mp3",
                                     uniqueId: "someone-else", extra: extra))

    #expect(await waiting.value == nil)
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "downloadFile" })
}

@Test("a delete follows a stale row back to the current message")
func removeFollowsTheIdentity() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    let file = TdFile(fileId: 5, uniqueId: "u9006", message: origin(.audio, trackId: "u9006"))

    let waiting = Task { await downloader.remove(file) }
    let lookup = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 5, active: false, completed: true,
                                     path: "/tmp/doni/files/5.mp3", uniqueId: "someone-else",
                                     extra: lookup))
    let message = try await downloadExtra(of: session.transport, type: "getMessage")
    session.transport.queue(audioMessage(audioId: 9006, audioUniqueId: "u9006", extra: message))
    let ask = try await downloadExtra(of: session.transport, type: "deleteFile")
    session.transport.queue(#"{"@type":"ok","@extra":"\#(ask)"}"#)

    #expect(await waiting.value == true)
    let request = try #require(requestFields(of: session.transport, type: "deleteFile"))
    #expect(request["file_id"]?.int == 9006)
}

@Test("a file with no identity and no message keeps the old numeric behaviour")
func numberWithoutIdentityIsUsedAsItWas() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.readyPath(TdFile(fileId: 9007, uniqueId: nil)) }
    let extra = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 9007, active: false, completed: true,
                                     path: "/tmp/doni/files/9007.mp3", extra: extra))

    #expect(await waiting.value == "/tmp/doni/files/9007.mp3")
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "getMessage" })
}

@Test("a stale song row is refreshed from its own message and plays")
func staleAudioRowIsRefreshedFromItsMessage() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    let file = TdFile(fileId: 5, uniqueId: "wanted", message: origin(.audio))

    let waiting = Task { await downloader.path(file, priority: TdFileDownloader.audioPriority) }
    let check = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 5, active: false, completed: true, path: "/wrong.mp3",
                                     uniqueId: "someone-else", extra: check))
    let message = try await downloadExtra(of: session.transport, type: "getMessage")
    session.transport.queue(audioMessage(audioId: 9008, audioUniqueId: "wanted", extra: message))
    let ask = try await downloadExtra(of: session.transport, type: "downloadFile")
    session.transport.queue(fileJSON(id: 9008, active: false, completed: true,
                                     path: "/tmp/doni/files/9008.mp3",
                                     uniqueId: "wanted", extra: ask))

    #expect(await waiting.value == "/tmp/doni/files/9008.mp3")
    let request = try #require(requestFields(of: session.transport, type: "getMessage"))
    #expect(request["chat_id"]?.int == 44)
    #expect(request["message_id"]?.int == 55)
}

@Test("a stale cover row is refreshed to the exact named cover")
func staleCoverRowIsRefreshedToTheExactCover() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    let file = TdFile(fileId: 5, uniqueId: "cover-wanted", message: origin(.cover))

    let waiting = Task { await downloader.path(file) }
    let check = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 5, active: false, completed: true, path: "/wrong.jpg",
                                     uniqueId: "someone-else", extra: check))
    let message = try await downloadExtra(of: session.transport, type: "getMessage")
    session.transport.queue(audioMessage(
        audioId: 9100, audioUniqueId: "wanted",
        cover: coverJSON(id: 9998, uniqueId: "cover-other", width: 600),
        externalCovers: [coverJSON(id: 9009, uniqueId: "cover-wanted")], extra: message
    ))
    let ask = try await downloadExtra(of: session.transport, type: "downloadFile")
    session.transport.queue(fileJSON(id: 9009, active: false, completed: true,
                                     path: "/tmp/doni/files/9009.jpg",
                                     uniqueId: "cover-wanted", extra: ask))

    #expect(await waiting.value == "/tmp/doni/files/9009.jpg")
    let request = try #require(requestFields(of: session.transport, type: "downloadFile"))
    #expect(request["file_id"]?.int == 9009)
}

@Test("an unnamed generated cover is recovered only from its own song")
func generatedCoverIsRecoveredFromItsOwnSong() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    let file = TdFile(fileId: 5, uniqueId: nil, message: origin(.cover))

    let waiting = Task { await downloader.path(file) }
    let message = try await downloadExtra(of: session.transport, type: "getMessage")
    session.transport.queue(audioMessage(
        audioId: 9101, audioUniqueId: "wanted",
        cover: coverJSON(id: 9010, uniqueId: ""), extra: message
    ))
    let ask = try await downloadExtra(of: session.transport, type: "downloadFile")
    session.transport.queue(fileJSON(id: 9010, active: false, completed: true,
                                     path: "/tmp/doni/files/9010.jpg",
                                     uniqueId: "", extra: ask))

    #expect(await waiting.value == "/tmp/doni/files/9010.jpg")
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "getFile" })
}

@Test("a download response about other bytes is never returned")
func mismatchedDownloadResponseIsRefused() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(TdFile(fileId: 9011, uniqueId: "wanted")) }
    let check = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 9011, active: false, completed: false, path: "",
                                     uniqueId: "wanted", extra: check))
    let ask = try await downloadExtra(of: session.transport, type: "downloadFile")
    session.transport.queue(fileJSON(id: 9011, active: false, completed: true, path: "/wrong.mp3",
                                     uniqueId: "someone-else", extra: ask))

    #expect(await waiting.value == nil)
}

@Test("an update about other bytes is never delivered to a waiting song")
func mismatchedUpdateIsRefused() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.path(TdFile(fileId: 9012, uniqueId: "wanted")) }
    let check = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 9012, active: false, completed: false, path: "",
                                     uniqueId: "wanted", extra: check))
    let ask = try await downloadExtra(of: session.transport, type: "downloadFile")
    session.transport.queue(fileJSON(id: 9012, active: true, completed: false, path: "",
                                     uniqueId: "wanted", extra: ask))
    session.transport.queue(updateFile(fileJSON(id: 9012, active: false, completed: true,
                                                path: "/wrong.mp3", uniqueId: "someone-else")))

    #expect(await waiting.value == nil)
}

@Test("a message about another song cannot repair a stale row")
func wrongMessageIsRefused() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    let file = TdFile(fileId: 5, uniqueId: "wanted", message: origin(.audio))

    let waiting = Task { await downloader.path(file) }
    let check = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 5, active: false, completed: true, path: "/wrong.mp3",
                                     uniqueId: "someone-else", extra: check))
    let message = try await downloadExtra(of: session.transport, type: "getMessage")
    session.transport.queue(audioMessage(audioId: 9013, audioUniqueId: "another-song",
                                         extra: message))

    #expect(await waiting.value == nil)
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "downloadFile" })
}

@Test("every request the downloader sends exists in the pinned TDLib schema")
func requestsExistInPinnedSchema() throws {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    let source = try String(
        contentsOf: root.appendingPathComponent(
            "Packages/TdSession/Sources/TdSession/TdFileDownloader.swift"
        ), encoding: .utf8
    )
    let schema = try String(
        contentsOf: root.appendingPathComponent("Vendor/src/td/td/generate/scheme/td_api.tl"),
        encoding: .utf8
    )
    let expression = try NSRegularExpression(pattern: #"flow\.request\(\s*"([A-Za-z0-9]+)""#)
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    let names = Set(expression.matches(in: source, range: range).compactMap { match in
        Range(match.range(at: 1), in: source).map { String(source[$0]) }
    })
    #expect(!names.isEmpty)
    for name in names {
        #expect(schema.contains("\n\(name) "), "TDLib has no request named \(name)")
    }
}

/// The answer to `getFileDownloadedPrefixSize` (`td_api.tl:10814`) — the only thing that reports
/// readiness in the middle of a file.
private func prefixJSON(size: Int, extra: String) -> String {
    #"""
    {"@type":"fileDownloadedPrefixSize","@extra":"\#(extra)","size":\#(size)}
    """#
}

@Test("the state reports the file's length and the one window updateFile admits to")
func stateReadsTheLocalFile() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task { await downloader.state(TdFile(fileId: 8010, uniqueId: nil)) }
    let asked = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 8010, active: true, completed: false, path: "/tmp/song.mp3",
                                     offset: 128, prefix: 64, size: 999, extra: asked))

    let state = try #require(await waiting.value)
    #expect(state.path == "/tmp/song.mp3")
    #expect(state.size == 999)
    #expect(!state.isComplete)
    #expect(state.downloadOffset == 128)
    #expect(state.readyFromDownloadOffset == 64)
    #expect(state.canDownload)
    // A state is a look, not an ask: nothing here starts a download.
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "downloadFile" })
}

@Test("a range in the middle of a file is served from the ready bitmask")
func readAsksTheBitmaskNotThePrefix() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    // TDLib's own declared window starts at 12 and says nothing is ready, so the only way these six
    // bytes can be handed back is the bitmask answer for offset 4 (`FileManager.cpp:1043-1058`).
    let (url, bytes) = try written("0123456789ABCDEFGH")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let waiting = Task { await downloader.read(TdFile(fileId: 8011, uniqueId: nil), at: 4, upTo: 10) }
    let looked = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 8011, active: true, completed: false, path: url.path,
                                     offset: 12, prefix: 0, size: bytes.count, extra: looked))
    let probed = try await downloadExtra(of: session.transport, type: "getFileDownloadedPrefixSize")
    session.transport.queue(prefixJSON(size: 6, extra: probed))

    let got = try #require(await waiting.value)
    #expect(Array(got) == Array(bytes[4..<10]))
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "downloadFile" })
}

@Test("bytes nobody has confirmed ready are not read at all")
func readRefusesWithoutAnAnswer() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    let (url, bytes) = try written("0123456789ABCDEFGH")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let waiting = Task { await downloader.read(TdFile(fileId: 8012, uniqueId: nil), at: 2, upTo: 4) }
    let looked = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 8012, active: true, completed: false, path: url.path,
                                     prefix: 18, size: bytes.count, extra: looked))
    let probed = try await downloadExtra(of: session.transport, type: "getFileDownloadedPrefixSize")
    session.transport.queue(#"{"@type":"error","@extra":"\#(probed)","code":400,"message":"FILE_INVALID"}"#)

    #expect(await waiting.value == nil)
}

@Test("a whole file is read to its end without asking TDLib about readiness")
func readOfAWholeFileSkipsTheProbe() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)
    let (url, bytes) = try written("0123456789AB")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let waiting = Task { await downloader.read(TdFile(fileId: 8013, uniqueId: nil), at: 8, upTo: 4096) }
    let looked = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 8013, active: false, completed: true, path: url.path,
                                     size: bytes.count, extra: looked))

    let got = try #require(await waiting.value)
    #expect(Array(got) == Array(bytes[8...]))
    #expect(session.transport.decodedRequests.allSatisfy {
        $0.type != "getFileDownloadedPrefixSize"
    })
}

@Test("a window ask moves the download rather than starting a second one")
func askSendsTheWindow() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task {
        await downloader.ask(TdFile(fileId: 8014, uniqueId: nil), window: 4096, bytes: 512)
    }
    let asked = try await downloadExtra(of: session.transport)
    session.transport.queue(fileJSON(id: 8014, active: true, completed: false, path: "",
                                     offset: 4096, prefix: 0, extra: asked))

    let state = try #require(await waiting.value)
    #expect(state.downloadOffset == 4096)
    let request = try #require(requestFields(of: session.transport, type: "downloadFile"))
    #expect(request["offset"]?.int == 4096)
    #expect(request["limit"]?.int == 512)
    // A streaming window is the song's own priority: never the cover's.
    #expect(request["priority"]?.int == 16)
    #expect(request["synchronous"]?.bool == false)
}

@Test("a window asked on somebody else's row number is refused")
func askChecksIdentity() async throws {
    let session = makeSession()
    defer { session.client.close() }
    let downloader = TdFileDownloader(flow: session.flow)

    let waiting = Task {
        await downloader.ask(TdFile(fileId: 8015, uniqueId: "mine"), window: 0, bytes: 512)
    }
    let check = try await downloadExtra(of: session.transport, type: "getFile")
    session.transport.queue(fileJSON(id: 8015, active: false, completed: true, path: "/mine.mp3",
                                     uniqueId: "someone-else", extra: check))

    #expect(await waiting.value == nil)
    #expect(session.transport.decodedRequests.allSatisfy { $0.type != "downloadFile" })
}
