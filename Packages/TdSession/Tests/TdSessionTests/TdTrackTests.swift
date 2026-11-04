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
    #expect(value.miniArtwork == nil, "a document's minithumbnail is a drawn file icon")
}

/// `td_api.tl:361` — `minithumbnail width height data:bytes`, and TDLib's JSON
/// writes `bytes` as base64. A real channel carries this on two thirds of its
/// audios, which is why the list can show cover art without downloading a file.
private func audioWithArtwork(_ data: String?) -> TdJSON {
    var audio: [String: TdJSON] = [
        "@type": .string("audio"), "duration": .int(200),
        "title": .string("Lạc Trôi"), "performer": .string("Sơn Tùng M-TP"),
        "file_name": .string("lac-troi.mp3"), "mime_type": .string("audio/mpeg"),
        "audio": .object([
            "@type": .string("file"), "id": .int(90), "size": .int(5_000_000),
            "local": .object(["@type": .string("localFile"), "path": .string("")]),
            "remote": .object([
                "@type": .string("remoteFile"), "unique_id": .string("CAACAgEAAxUZ")
            ])
        ])
    ]
    if let data {
        audio["album_cover_minithumbnail"] = .object([
            "@type": .string("minithumbnail"), "width": .int(40), "height": .int(30),
            "data": .string(data)
        ])
    }
    return .object([
        "@type": .string("message"), "id": .int(600), "chat_id": .int(-1001234567890),
        "date": .int(1_730_000_200),
        "content": .object([
            "@type": .string("messageAudio"), "audio": .object(audio),
            "caption": .object(["@type": .string("formattedText"), "text": .string("")])
        ])
    ])
}

@Test("cover art comes with the message and needs no download")
func miniArtworkDecodes() throws {
    let jpegBase64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA=="
    let value = try #require(TdTrack(message: audioWithArtwork(jpegBase64)))
    #expect(value.miniArtwork == Data(base64Encoded: jpegBase64))

    let bare = try #require(TdTrack(message: audioWithArtwork(nil)))
    #expect(bare.miniArtwork == nil)
}

@Test("base64 that is not base64 is no artwork, not a crash")
func unreadableArtworkIsIgnored() throws {
    let value = try #require(TdTrack(message: audioWithArtwork("not base64 at all !!")))
    #expect(value.miniArtwork == nil)
    #expect(value.displayTitle == "Lạc Trôi", "the track is still listable")
}

/// One `thumbnail` (`td_api.tl:393`), which is the shape all three of an audio's covers arrive in.
///
/// `bytes` is what the file behind it promises: 0 for every `external_album_covers` entry of the
/// measured channel — TDLib generates those from the title and performer and has no size for them
/// until the server has made the picture (`AudiosManager.cpp:53-67`) — and 6,635 to 31,205 for the
/// 112 audios that carry a real `album_cover_thumbnail`. `fileId` is nil for a thumbnail with no
/// file object at all.
private struct Thumbnail {
    var width: Int
    var fileId: Int?
    var bytes: Int = 0
}

private func thumbnailJSON(_ thumbnail: Thumbnail) -> TdJSON {
    var fields: [String: TdJSON] = [
        "@type": .string("thumbnail"),
        "width": .int(Int64(thumbnail.width)),
        "height": .int(Int64(thumbnail.width))
    ]
    if let fileId = thumbnail.fileId {
        fields["file"] = .object([
            "@type": .string("file"), "id": .int(Int64(fileId)),
            "size": .int(Int64(thumbnail.bytes)),
            "expected_size": .int(Int64(thumbnail.bytes))
        ])
    }
    return .object(fields)
}

/// A real channel's every audio carries `external_album_covers` (`td_api.tl:583`) with two
/// `thumbnail` objects (`td_api.tl:393`) — measured as 100×100 then 600×600 on 168 of 168
/// messages, both of them with zero bytes. Sizes here are invented; the shape is the measured one.
private func audioWithCovers(_ covers: [Thumbnail], thumbnail: Thumbnail? = nil) -> TdJSON {
    var audio: [String: TdJSON] = [
        "@type": .string("audio"), "duration": .int(210),
        "title": .string("Lạc Trôi"), "performer": .string("Sơn Tùng M-TP"),
        "file_name": .string("lac-troi.mp3"), "mime_type": .string("audio/mpeg"),
        "audio": .object([
            "@type": .string("file"), "id": .int(92), "size": .int(5_000_000),
            "local": .object(["@type": .string("localFile"), "path": .string("")]),
            "remote": .object([
                "@type": .string("remoteFile"), "unique_id": .string("CAACAgEAAxUb")
            ])
        ]),
        "external_album_covers": .array(covers.map(thumbnailJSON))
    ]
    if let thumbnail {
        audio["album_cover_thumbnail"] = thumbnailJSON(thumbnail)
    }
    return .object([
        "@type": .string("message"), "id": .int(602), "chat_id": .int(-1001234567890),
        "date": .int(1_730_000_400),
        "content": .object([
            "@type": .string("messageAudio"),
            "audio": .object(audio),
            "caption": .object(["@type": .string("formattedText"), "text": .string("")])
        ])
    ])
}

@Test("the sharp cover is the widest of the pair the channel sends")
func widestCoverWins() throws {
    let measured = try #require(TdTrack(message: audioWithCovers([
        Thumbnail(width: 100, fileId: 401), Thumbnail(width: 600, fileId: 402)
    ])))
    #expect(measured.coverFileId == 402)

    let reversed = try #require(TdTrack(message: audioWithCovers([
        Thumbnail(width: 600, fileId: 402), Thumbnail(width: 100, fileId: 401)
    ])))
    #expect(reversed.coverFileId == 402, "the largest is chosen by width, not by position")

    let alone = try #require(TdTrack(message: audioWithCovers([Thumbnail(width: 100, fileId: 401)])))
    #expect(alone.coverFileId == 401)

    let none = try #require(TdTrack(message: audioWithCovers([])))
    #expect(none.coverFileId == nil, "a track with no cover announced falls back to the gradient")
}

@Test("a thumbnail with bytes outranks a bigger one that has none")
func realThumbnailBeatsGeneratedCover() throws {
    // The measured 112 of 168: a 320×240 `album_cover_thumbnail` of 6.6 KB alongside the pair of
    // generated covers claiming 100 and 600 pixels with no bytes behind either.
    let track = try #require(TdTrack(message: audioWithCovers(
        [Thumbnail(width: 100, fileId: 401), Thumbnail(width: 600, fileId: 402)],
        thumbnail: Thumbnail(width: 320, fileId: 403, bytes: 6_635)
    )))
    #expect(track.coverFileId == 403, "the one that can be downloaded now is the sharp cover")

    let smallerButReal = try #require(TdTrack(message: audioWithCovers(
        [Thumbnail(width: 600, fileId: 402, bytes: 0)],
        thumbnail: Thumbnail(width: 90, fileId: 404, bytes: 1)
    )))
    #expect(smallerButReal.coverFileId == 404, "bytes count before width does")

    let bothReal = try #require(TdTrack(message: audioWithCovers(
        [Thumbnail(width: 600, fileId: 402, bytes: 40_000)],
        thumbnail: Thumbnail(width: 320, fileId: 403, bytes: 6_635)
    )))
    #expect(bothReal.coverFileId == 402, "and among ones that can all be fetched, the widest still wins")
}

@Test("a document announces no album cover")
func documentHasNoCover() throws {
    let document = try #require(TdTrack(message: json(looseDocument)))
    #expect(document.coverFileId == nil, "only audio posts carry `external_album_covers`")
}

@Test("a thumbnail with no file behind it is not a cover")
func coverWithoutFileIdIsIgnored() throws {
    let value = try #require(TdTrack(message: audioWithCovers([
        Thumbnail(width: 600, fileId: nil)
    ])))
    #expect(value.coverFileId == nil)
    #expect(value.displayTitle == "Lạc Trôi", "and the row still shows the song")
}

/// The shape a posting bot sends: the tag cut at about 64 characters and the whole name
/// repeated in the caption. Titles here are invented — a real channel's message content
/// stays out of the repo, as the brief requires.
private func botPosted(title: String, caption: String) -> TdJSON {
    .object([
        "@type": .string("message"), "id": .int(601), "chat_id": .int(-1001234567890),
        "date": .int(1_730_000_300),
        "content": .object([
            "@type": .string("messageAudio"),
            "audio": .object([
                "@type": .string("audio"), "duration": .int(3600),
                "title": .string(title), "performer": .string("DJ Không Tên"),
                "file_name": .string("nonstop.mp3"), "mime_type": .string("audio/mpeg"),
                "audio": .object([
                    "@type": .string("file"), "id": .int(91), "size": .int(9_000_000),
                    "local": .object(["@type": .string("localFile"), "path": .string("")]),
                    "remote": .object([
                        "@type": .string("remoteFile"), "unique_id": .string("CAACAgEAAxUa")
                    ])
                ])
            ]),
            "caption": .object([
                "@type": .string("formattedText"), "text": .string(caption), "entities": .array([])
            ])
        ])
    ])
}

private let cutTag = "MỘT BÀI NONSTOP REMIX (BẢN HOT TIKTOK) - MỘT BÀI NONSTOP…"
private let wholeName = "MỘT BÀI NONSTOP REMIX (BẢN HOT TIKTOK) - MỘT BÀI NONSTOP CỰC MẠNH 2025"

@Test("a title the posting bot cut is repaired from the caption's own name line")
func cutTitleRepairedFromCaption() throws {
    let value = try #require(TdTrack(
        message: botPosted(title: cutTag, caption: """
        Tiêu đề: \(wholeName)
        Kênh: Mix Team
        Nguồn: @NhacBot
        """)
    ))
    #expect(value.displayTitle == wholeName)
    #expect(value.title == wholeName, "repaired at the message boundary, so search and the store see it too")
}

@Test("the name line is found under Bài hát as well as under Tiêu đề")
func songKeyRepairsToo() throws {
    let value = try #require(TdTrack(
        message: botPosted(title: "Tương Tư…", caption: """
        Bài hát: Tương Tư Một Người Ra Đi
        Thể hiện: Minh Như
        """)
    ))
    #expect(value.displayTitle == "Tương Tư Một Người Ra Đi")
    #expect(value.displayPerformer == "DJ Không Tên", "the tag performer is not the caption's, and stays the tag's")
}

@Test("the bot's case and its spacing do not hide a match")
func foldedMatchRepairs() throws {
    let lower = try #require(TdTrack(
        message: botPosted(title: "tương tư…", caption: "Bài hát: Tương Tư Một Người Ra Đi")
    ))
    #expect(lower.displayTitle == "Tương Tư Một Người Ra Đi")

    let spaced = try #require(TdTrack(
        message: botPosted(title: "Tương  tư…", caption: "Bài hát: Tương tư hai người ở lại")
    ))
    #expect(spaced.displayTitle == "Tương tư hai người ở lại")
}

@Test("a caption that is not the same name leaves the bot's cut in place")
func unrelatedCaptionKeepsTheCut() throws {
    let value = try #require(TdTrack(
        message: botPosted(title: cutTag, caption: "Tiêu đề: MỘT BÀI KHÁC HOÀN TOÀN DÀI RA ĐÂY NÈ")
    ))
    #expect(value.displayTitle == cutTag)

    let shorter = try #require(TdTrack(message: botPosted(title: cutTag, caption: "Tiêu đề: MỘT")))
    #expect(shorter.displayTitle == cutTag, "a caption shorter than the cut is not the same name")
}

@Test("a duration line is never read as a name")
func durationLineIsNotAName() throws {
    // The real layout puts `Loại:` inside the duration line, so a parser that split on any
    // colon would find a name that is not one.
    let value = try #require(TdTrack(
        message: botPosted(title: cutTag, caption: "Thời lượng: 1:11:37  Loại: Youtube")
    ))
    #expect(value.displayTitle == cutTag)
}

@Test("an untouched title is left exactly as the tag wrote it")
func wholeTagTitleIsUntouched() throws {
    let value = try #require(TdTrack(
        message: botPosted(title: "Lạc Trôi", caption: "Tiêu đề: Lạc Trôi — Đức Phúc Và Bạn Bè")
    ))
    #expect(value.displayTitle == "Lạc Trôi", "only a cut tag is ever replaced")
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

