import Foundation
import Testing
@testable import TdSession

/// A `chat` object (`td_api.tl:4080`) whose `photo` is a `chatPhotoInfo` (`:784`) wearing whatever
/// the test wants, in the shape TDLib's JSON has it: each variant is a `file` (`:326`) whose remote
/// half carries the MTProto identity.
private func chat(_ photo: TdJSON?) -> TdJSON {
    var fields: [String: TdJSON] = [
        "@type": .string("chat"), "id": .int(-1001), "title": .string("Nhạc Remix")
    ]
    if let photo { fields["photo"] = photo }
    return .object(fields)
}

/// One `file` of the `chatPhotoInfo` family.
private func variant(_ id: Int, uniqueId: String? = nil) -> TdJSON {
    var file: [String: TdJSON] = ["@type": .string("file"), "id": .int(Int64(id))]
    if let uniqueId {
        file["remote"] = .object(["@type": .string("fileRemotePersistent"),
                                  "unique_id": .string(uniqueId)])
    } else {
        file["remote"] = .object(["@type": .string("fileRemoteUnknown")])
    }
    return .object(file)
}

private func photoInfo(_ fields: [String: TdJSON]) -> TdJSON {
    var photo = fields
    photo["@type"] = .string("chatPhotoInfo")
    return .object(photo)
}

@Suite("TdChatPhoto")
struct TdChatPhotoTests {
    @Test("the small variant is the one asked for, and its identity is its own")
    func prefersSmall() throws {
        let photo = try #require(TdChatPhoto(chat: chat(photoInfo([
            "small": variant(42, uniqueId: "AAA="), "big": variant(43, uniqueId: "BBB=")
        ]))))
        // 160×160 (`td_api.tl:779`) is five times a 30 pt mark, and a fraction of the bytes of the
        // 640×640 beside it (`:780`), so the smaller is the one worth waiting on.
        #expect(photo.fileId == 42)
        #expect(photo.uniqueId == "AAA=")
    }

    @Test("a chat with only the big variant still has a picture")
    func fallsBackToBig() throws {
        let photo = try #require(TdChatPhoto(chat: chat(photoInfo([
            "small": variant(0), "big": variant(43, uniqueId: "BBB=")
        ]))))
        #expect(photo.fileId == 43)
        #expect(photo.uniqueId == "BBB=")
    }

    @Test("the identity comes from the same variant as the number")
    func neverPairsVariants() throws {
        // A `small` TDLib has a row for but no bytes of, and a `big` it has both for: taking the
        // number from one and the identity from the other would file the downloaded picture under
        // the wrong name.
        let photo = try #require(TdChatPhoto(chat: chat(photoInfo([
            "small": variant(0, uniqueId: "AAA="), "big": variant(43, uniqueId: "BBB=")
        ]))))
        #expect(photo.fileId == 43)
        #expect(photo.uniqueId == "BBB=")
    }

    @Test("a chat that never set a photo has no picture")
    func emptyPhotoIsNothing() throws {
        #expect(TdChatPhoto(chat: chat(nil)) == nil)
        #expect(TdChatPhoto(chat: chat(photoInfo([:]))) == nil)
        #expect(TdChatPhoto(chat: chat(photoInfo(["small": variant(0)]))) == nil)
    }

    @Test("a number without an identity is still a number")
    func unknownRemoteKeepsTheId() throws {
        // `fileRemoteUnknown` is what TDLib answers before it has looked the file up, so the row
        // knows what to ask for and only that.
        let photo = try #require(TdChatPhoto(chat: chat(photoInfo(["small": variant(42)]))))
        #expect(photo.fileId == 42)
        #expect(photo.uniqueId == nil)
    }

    @Test("an empty identity is not an identity")
    func emptyUniqueIdIsNothing() throws {
        let photo = try #require(TdChatPhoto(chat: chat(photoInfo([
            "small": variant(42, uniqueId: "")
        ]))))
        #expect(photo.uniqueId == nil)
    }
}
