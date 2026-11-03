import Foundation
import Testing
@testable import TdSession

/// A `messageAudio` as TDLib actually sends it: tags on the audio, the file
/// nested under `audio:`, the dedupe key under `remote:`.
private let taggedAudio = #"""
{
  "@type": "message",
  "id": 551,
  "chat_id": -1001234567890,
  "date": 1730000000,
  "content": {
    "@type": "messageAudio",
    "audio": {
      "@type": "audio",
      "duration": 245,
      "title": "Đêm Lay-Lay",
      "performer": "Minh Như",
      "file_name": "dem-lay-lay.mp3",
      "mime_type": "audio/mpeg",
      "audio": {
        "@type": "file",
        "id": 77,
        "size": 9876543,
        "expected_size": 9876543,
        "local": {"@type": "localFile", "path": "", "can_be_downloaded": true,
                  "can_be_deleted": false, "is_downloading_active": false,
                  "is_downloading_completed": false, "download_offset": 0,
                  "downloaded_prefix_size": 0, "downloaded_size": 0},
        "remote": {"@type": "remoteFile", "id": "7f", "unique_id": "CAACAgEAAxUE",
                   "is_uploading_active": false, "is_uploading_completed": true,
                   "uploaded_size": 0}
      }
    },
    "caption": {"@type": "formattedText", "text": "", "entities": []}
  }
}
"""#

/// The same song posted as a bare file: no tags, no duration, a mime TDLib
/// copied from the uploader's OS.
private func documentFixture(caption: String) -> String {
    #"""
{
  "@type": "message",
  "id": 552,
  "chat_id": -1001234567890,
  "date": 1730000100,
  "content": {
    "@type": "messageDocument",
    "document": {
      "@type": "document",
      "file_name": "Lac Troi - Duc Phuc.mp3",
      "mime_type": "application/octet-stream",
      "document": {
        "@type": "file",
        "id": 78,
        "size": 0,
        "expected_size": 4120000,
        "local": {"@type": "localFile", "path": "/var/Doni/files/78.mp3",
                  "can_be_downloaded": true, "can_be_deleted": true,
                  "is_downloading_active": false, "is_downloading_completed": true,
                  "download_offset": 0, "downloaded_prefix_size": 0, "downloaded_size": 0},
        "remote": {"@type": "remoteFile", "id": "8a", "unique_id": "CAACAgEAAxUF",
                   "is_uploading_active": false, "is_uploading_completed": true,
                   "uploaded_size": 0}
      }
    },
    "caption": {"@type": "formattedText", "text": "\#(caption)", "entities": []}
  }
}
"""#
}

private let looseDocument = documentFixture(caption: "Lạc Trôi — Đức Phúc")
private let looseDocumentWithoutCaption = documentFixture(caption: "")

private let photoMessage = #"""
{"@type": "message", "id": 553, "chat_id": -1001234567890,
 "content": {"@type": "messagePhoto", "photo": {"@type": "photo"}}}
"""#

private func json(_ text: String) -> TdJSON {
    guard let value = TdJSON.parse(text) else { Issue.record("fixture is not JSON"); return .null }
    return value
}

@Test("an audio message keeps its tags, its size and its unique id")
func audioTrackDecodes() throws {
    let value = try #require(TdTrack(message: json(taggedAudio)))
    #expect(value.messageId == 551)
    #expect(value.chatId == -1001234567890)
    #expect(value.origin == .audio)
    #expect(value.fileId == 77)
    #expect(value.uniqueId == "CAACAgEAAxUE")
    #expect(value.displayTitle == "Đêm Lay-Lay")
    #expect(value.displayPerformer == "Minh Như")
    #expect(value.duration == 245)
    #expect(value.size == 9876543)
    #expect(value.localPath == nil)
    #expect(value.isDownloaded == false)
    #expect(value.isAudio)
}

@Test("a document is a track by its extension, and reads its name off the caption")
func documentTrackDecodes() throws {
    let value = try #require(TdTrack(message: json(looseDocument)))
    #expect(value.origin == .document)
    #expect(value.isAudio)
    #expect(value.duration == nil)
    #expect(value.size == 4120000, "expected_size stands in while the server size is unknown")
    #expect(value.displayTitle == "Lạc Trôi — Đức Phúc")
    #expect(value.displayPerformer.isEmpty)
    #expect(value.fileNameStem == "Lac Troi - Duc Phuc")
    #expect(value.localPath == "/var/Doni/files/78.mp3")
    #expect(value.isDownloaded)
}

@Test("the file name is the last fallback when there is no caption either")
func documentWithoutCaption() throws {
    let value = try #require(TdTrack(message: json(looseDocumentWithoutCaption)))
    #expect(value.caption.isEmpty)
    #expect(value.displayTitle == "Lac Troi - Duc Phuc")
}

@Test("anything that is not a file the app can play decodes to nothing")
func otherContentIsIgnored() {
    #expect(TdTrack(message: json(photoMessage)) == nil)
    #expect(TdTrack(message: .object([:])) == nil)
    let video = TdJSON.object([
        "@type": .string("message"), "id": .int(1), "chat_id": .int(2),
        "content": .object(["@type": .string("messageVideo")])
    ])
    #expect(TdTrack(message: video) == nil)
}

@Test("a document without an audio extension is not a song")
func nonAudioDocumentRejected() throws {
    let zip = TdJSON.object([
        "@type": .string("message"), "id": .int(9), "chat_id": .int(2),
        "content": .object([
            "@type": .string("messageDocument"),
            "document": .object([
                "@type": .string("document"), "file_name": .string("rules.zip"),
                "mime_type": .string("application/zip"),
                "document": .object([
                    "@type": .string("file"), "id": .int(3), "size": .int(10),
                    "expected_size": .int(10),
                    "local": .object(["@type": .string("localFile"), "path": .string("")]),
                    "remote": .object([
                        "@type": .string("remoteFile"), "unique_id": .string("CAAD")
                    ])
                ])
            ])
        ])
    ])
    let value = try #require(TdTrack(message: zip))
    #expect(value.isAudio == false)
}

@Test("a page finds the oldest id it holds and only an empty one ends the walk")
func pageCursor() {
    let full = (1...TdChannelReader.pageSize).map { index in
        TdJSON.object(["id": .int(Int64(index)), "chat_id": .int(1)])
    }
    let page = TdHistoryPage(messages: full, totalCount: 4_200)
    #expect(page.oldestMessageId == 1)
    #expect(page.totalCount == 4_200)
    #expect(page.isLast == false)

    // TDLib answers with the messages it has, so a short page in the middle of a
    // channel with gaps still has older posts.
    let short = TdHistoryPage(messages: Array(full.prefix(7)), totalCount: nil)
    #expect(short.isLast == false)
    #expect(short.oldestMessageId == 1)
    #expect(short.trackCount == 0, "a page of stubs holds no tracks")

    let empty = TdHistoryPage(messages: [], totalCount: 0)
    #expect(empty.oldestMessageId == nil)
    #expect(empty.isLast)
}

@Test("a page keeps only the playable messages")
func pageCollectsTracks() {
    let page = TdHistoryPage(
        messages: [json(taggedAudio), json(looseDocument), json(photoMessage)],
        totalCount: 3
    )
    #expect(page.messages.count == 3)
    #expect(page.trackCount == 2)
    #expect(page.tracks.map(\.messageId) == [551, 552])
    #expect(page.oldestMessageId == 551)
}

private let readerParameters = TdParameters(
    apiId: 1,
    apiHash: "deadbeef",
    databaseDirectory: "/tmp/doni/db",
    filesDirectory: "/tmp/doni/files",
    deviceModel: "iPhone 16e",
    systemVersion: "26.1",
    applicationVersion: "0.1"
)

private struct FixedKey: TdDatabaseKeyProviding {
    func databaseEncryptionKey() -> String { "a2V5" }
}

/// A stand-in for TDLib that answers each request according to its `@type`,
/// echoing the `@extra` the client correlates on.
private func startChannelServer(
    _ transport: FakeTransport,
    chatReply: @escaping @Sendable (String) -> String
) -> Task<Void, Never> {
    Task.detached {
        var answered: Set<String> = []
        while !Task.isCancelled {
            for request in transport.decodedRequests {
                guard let extra = request["@extra"]?.string, !answered.contains(extra) else { continue }
                answered.insert(extra)
                switch request.type {
                case "searchPublicChat":
                    transport.queue(chatReply(extra))
                case "getChatHistory":
                    transport.queue(
                        #"{"@type":"messages","@extra":"\#(extra)","messages":[]}"#
                    )
                default:
                    transport.queue(#"{"@type":"ok","@extra":"\#(extra)"}"#)
                }
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}

private func makeReader(_ transport: FakeTransport) -> TdChannelReader {
    let client = TdClient(transport: transport, clientId: 1)
    client.start(timeout: 0.02)
    return TdChannelReader(
        flow: TdLoginFlow(client: client, parameters: readerParameters, keyProvider: FixedKey())
    )
}

@Test("the reader sends searchPublicChat with a bare username, then getChatHistory")
func readerRequests() async throws {
    let transport = FakeTransport()
    let responder = startChannelServer(transport) { extra in
        #"{"@type":"chat","@extra":"\#(extra)","id":-1001234567890,"title":"VN Music Remix"}"#
    }
    defer { responder.cancel() }

    let reader = makeReader(transport)
    let channel = try await reader.channel(username: "https://t.me/VNMusicRemix")
    #expect(channel.chatId == -1001234567890)
    #expect(channel.username == "VNMusicRemix")
    #expect(channel.title == "VN Music Remix")

    let page = try await reader.page(chatId: channel.chatId)
    #expect(page.messages.isEmpty)
    #expect(page.isLast)

    let sent = transport.decodedRequests
    let search = try #require(sent.first { $0.type == "searchPublicChat" })
    #expect(search["username"]?.string == "VNMusicRemix")
    let history = try #require(sent.first { $0.type == "getChatHistory" })
    #expect(history["chat_id"]?.int == -1001234567890)
    #expect(history["from_message_id"]?.int == 0)
    #expect(history["limit"]?.int == Int64(TdChannelReader.pageSize))
    #expect(history["only_local"]?.bool == false)
}

@Test("a username TDLib does not resolve is a failure, not an empty channel")
func unknownChannelFails() async throws {
    let transport = FakeTransport()
    let responder = startChannelServer(transport) { extra in
        #"{"@type":"chats","@extra":"\#(extra)","chats":[]}"#
    }
    defer { responder.cancel() }

    let reader = makeReader(transport)
    await #expect(throws: TdChannelReader.Failure.channelNotFound("VNNope")) {
        _ = try await reader.channel(username: "@VNNope")
    }
    await #expect(throws: TdChannelReader.Failure.channelNotFound("https://t.me/")) {
        _ = try await reader.channel(username: "https://t.me/")
    }
}

@Test("a username comes in three shapes and leaves as one")
func handleParsing() {
    for input in ["VNMusicRemix", "@VNMusicRemix", "https://t.me/VNMusicRemix"] {
        let handle = input.split(separator: "/").last.map(String.init) ?? input
        #expect(handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")) == "VNMusicRemix", "\(input)")
    }
    #expect("https://t.me/".split(separator: "/").last.map(String.init) == "t.me")
}

