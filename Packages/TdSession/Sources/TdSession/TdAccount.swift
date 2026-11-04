import Foundation

/// The account the client is logged in as.
///
/// `getMe` (`td_api.tl:12388`) answers with a `user` (`:2806`), which is the only thing in TDLib
/// that says whose Telegram this is. The settings screen's account card is the one place the app
/// says it out loud, so the name and the identifier are read here rather than being guessed at from
/// what the library happens to hold.
public struct TdAccount: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let username: String
    /// The account's own picture at the size `getMe` carries it: the ~100 px JPEG inside the `user`
    /// object itself, which is what the header draws before anything has been downloaded. Nil for
    /// the millions of accounts that never set one, and for a `profile_photo` whose thumbnail has
    /// not been read yet — the glyph the header falls back to is the one Telegram itself draws for
    /// those.
    ///
    /// `user.profile_photo` (`td_api.tl:2806`) is a `profilePhoto` (`:776`) whose `minithumbnail`
    /// (`:361`) carries `data:bytes`, and TDLib's JSON writes `bytes` as base64 — the same encoding
    /// `TdTrack` reads an album cover out of.
    public let avatarData: Data?
    /// The same picture as a file, which is the only version of it big enough to be sharp. A
    /// minithumbnail is drawn at 28 pt on a 3× screen and a hundred-odd pixels is what it has to
    /// work with; `profile_photo.small` is capped at 160 px (`:776`), which is the size Telegram's
    /// own list avatars are, and it costs one download nobody waits on. Nil when the account has no
    /// picture at all.
    public let avatarFileId: Int?

    /// Nil when TDLib has not answered yet, or answered with something that carries no identifier —
    /// a `user` with no `id` is not an account, and a card that says "ID 0" would be a lie.
    public init?(user: TdJSON) {
        guard let id = user["id"]?.int, id != 0 else { return nil }
        self.id = id
        let first = user["first_name"]?.string ?? ""
        let last = user["last_name"]?.string ?? ""
        name = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        username = user["usernames"]?["active_usernames"]?[0]?.string ?? ""
        let photo = user["profile_photo"]
        avatarData = photo?["minithumbnail"]?["data"]?.string.flatMap { Data(base64Encoded: $0) }
        // `big` is the 640 px original; nothing in this app draws a person that big, but a photo
        // TDLib has only in the large size is still worth showing.
        if let small = photo?["small"]?["id"]?.int, small != 0 {
            avatarFileId = Int(small)
        } else if let big = photo?["big"]?["id"]?.int, big != 0 {
            avatarFileId = Int(big)
        } else {
            avatarFileId = nil
        }
    }
}
