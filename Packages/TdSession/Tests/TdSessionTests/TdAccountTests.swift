import Foundation
import Testing
@testable import TdSession

/// The `user` TDLib answers `getMe` with (`td_api.tl:2806`).
private func user(_ fields: [String: TdJSON]) -> TdJSON {
    var user: [String: TdJSON] = ["@type": .string("user"), "id": .int(77),
                                  "first_name": .string("Wica")]
    for (key, value) in fields { user[key] = value }
    return .object(user)
}

/// `profilePhoto` (`:776`) carries a `minithumbnail` (`:361`) whose `bytes` field TDLib serialises
/// as base64, which is what lets the header's avatar draw the account's picture without ordering a
/// file download — the same encoding `TdTrack` reads an album cover out of.
@Test func accountReadsItsProfilePhotoOutOfGetMe() throws {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xD9])
    let account = try #require(TdAccount(user: user([
        "profile_photo": .object([
            "@type": .string("profilePhoto"), "id": .int(9),
            "minithumbnail": .object([
                "@type": .string("minithumbnail"), "width": .int(100), "height": .int(100),
                "data": .string(jpeg.base64EncodedString()),
            ]),
        ]),
    ])))

    #expect(account.avatarData == jpeg)
}

/// An account that never set a picture — and one whose photo TDLib has not read yet — is the same
/// answer here: the avatar falls back to the glyph rather than to a broken image.
@Test func accountWithoutAPhotoCarriesNoAvatar() throws {
    let photoless = try #require(TdAccount(user: user([:])))
    #expect(photoless.avatarData == nil)

    let unread = try #require(TdAccount(user: user([
        "profile_photo": .object([
            "@type": .string("profilePhoto"), "id": .int(9),
            "minithumbnail": .null,
        ]),
    ])))
    #expect(unread.avatarData == nil)
}
