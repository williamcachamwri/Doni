import Foundation

/// The account the client is logged in as.
///
/// `getMe` (`td_api.tl:12388`) answers with a `user` (`:2806`) — the only thing in TDLib that says
/// whose Telegram this is, so the account card's name and identifier are read here rather than guessed.
public struct TdAccount: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let username: String
    /// The account's picture at the size `getMe` carries it: the ~100 px JPEG inside the `user`
    /// object, which the header draws before anything is downloaded. Nil for an account that never
    /// set one, and for a `profile_photo` whose thumbnail has not been read yet.
    ///
    /// `user.profile_photo` (`td_api.tl:2806`) is a `profilePhoto` (`:776`) whose `minithumbnail`
    /// (`:361`) carries `data:bytes`, which TDLib's JSON writes as base64.
    public let avatarData: Data?
    /// The same picture as a file, the only version big enough to be sharp: a minithumbnail is drawn
    /// at 28 pt on a 3× screen with a hundred-odd pixels to work with, while `profile_photo.small` is
    /// capped at 160 px (`:776`) — Telegram's own list-avatar size, for one download nobody waits on.
    public let avatarFileId: Int?
    /// The same picture's bytes as MTProto names them — the only name surviving a TDLib database
    /// rebuild. Without it the number above is asked for unverified, as it always was.
    public let avatarUniqueId: String?

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
        // `big` is the 640 px original; nothing here draws a person that big, but a photo TDLib only
        // has large is still worth showing. Number and identity come off the same variant: pairing one
        // picture's row with another's name is how a person wears somebody else's face.
        let photoFile = (photo?["small"]?["id"]?.int ?? 0) != 0 ? photo?["small"] : photo?["big"]
        if let file = photoFile, let number = file["id"]?.int, number != 0 {
            avatarFileId = Int(number)
            let remote = file["remote"]?["unique_id"]?.string
            avatarUniqueId = (remote?.isEmpty ?? true) ? nil : remote
        } else {
            avatarFileId = nil
            avatarUniqueId = nil
        }
    }
}
