import Foundation

/// What the player writes down about itself, in the reference's shape
/// (`PlaybackPersistence.swift:3-42`).
///
/// MeloX keeps the whole `[Song]` array; Doni keeps the queue's `unique_id`s and reads the rows back
/// out of SQLite. That is the same bargain the library already makes — `file_id` is TDLib's number
/// inside its own database (`td_api.tl:326`) and a row re-read from the store carries the one that is
/// true now — and it means a snapshot can never play a song the walk has since deleted.
struct PlaybackSnapshot: Codable, Equatable {
    /// The queue in the order it will be played, by `unique_id`.
    var queue: [String]
    /// The order the list was opened in, which is what turning shuffle off goes back to. MeloX
    /// keeps this as `shuffledOrder: [Int]` indices into its own array
    /// (`PlaybackPersistence.swift:9`); ids are the shape that survives a row leaving the store.
    var source: [String]
    /// Which of those rows is under the playhead.
    var currentIndex: Int
    /// The second the song had reached.
    var progress: TimeInterval
    var isShuffled: Bool
    var repeatMode: Player.RepeatMode
    var volume: Float
}

/// One key in `UserDefaults`, holding one JSON blob (`PlaybackPersistence.swift:21, 35-38`).
///
/// The library's SQLite file is the song store; this is not a second copy of it but the *plan* — what
/// was queued, in what order, and how far it had got. Nothing here is worth a database row, and
/// nothing here is a secret: the account's own material stays in Keychain and out of this file.
enum PlaybackPersistence {
    private static let key = "player.playbackSnapshot"

    static func save(_ snapshot: PlaybackSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> PlaybackSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
