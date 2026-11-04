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
    /// The account's own picture, as the ~100 px JPEG TDLib sends inside `getMe` itself, so the
    /// header's avatar needs no file download. Nil for the millions of accounts that never set one,
    /// and for a `profile_photo` whose thumbnail has not been read yet — the glyph the header falls
    /// back to is the one Telegram itself draws for those.
    ///
    /// `user.profile_photo` (`td_api.tl:2806`) is a `profilePhoto` (`:776`) whose `minithumbnail`
    /// (`:361`) carries `data:bytes`, and TDLib's JSON writes `bytes` as base64 — the same encoding
    /// `TdTrack` reads an album cover out of.
    public let avatarData: Data?

    /// Nil when TDLib has not answered yet, or answered with something that carries no identifier —
    /// a `user` with no `id` is not an account, and a card that says "ID 0" would be a lie.
    public init?(user: TdJSON) {
        guard let id = user["id"]?.int, id != 0 else { return nil }
        self.id = id
        let first = user["first_name"]?.string ?? ""
        let last = user["last_name"]?.string ?? ""
        name = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        username = user["usernames"]?["active_usernames"]?[0]?.string ?? ""
        let encoded = user["profile_photo"]?["minithumbnail"]?["data"]?.string
        avatarData = encoded.flatMap { Data(base64Encoded: $0) }
    }
}
