import Foundation
import Observation

/// A song, as far as the lyrics screen is concerned: enough to title a share sheet and
/// to notice that the song changed underneath it.
public struct Song: Hashable, Sendable {
    public let id: String
    public let name: String
    public let artistText: String
    public let album: Album?

    /// What the share sheet attaches as the song's link. Doni's songs are Telegram
    /// files, so this is the file on the phone rather than a page on the internet.
    public let shareURL: URL

    public init(
        id: String,
        name: String,
        artistText: String,
        album: Album? = nil,
        shareURL: URL
    ) {
        self.id = id
        self.name = name
        self.artistText = artistText
        self.album = album
        self.shareURL = shareURL
    }
}

public struct Album: Hashable, Sendable {
    public let artworkURL: URL?

    public init(artworkURL: URL?) {
        self.artworkURL = artworkURL
    }
}

/// The slice of the player the lyrics views watch.
///
/// Doni's real player is an `ObservableObject`; `@Environment(Type.self)` only accepts
/// `@Observable` types, and the copied views reach the player that way in six places. So
/// the lyrics package owns this small observable mirror and Doni pushes the player's state
/// into it — the position, whether it is playing, and a revision that moves when the user
/// seeks. The views never learn the difference, and they still read the extrapolated
/// position the way the reference does, between Doni's ticks.
@MainActor
@Observable
public final class PlayerStore {
    public var currentSong: Song?
    public var isPlaying = false

    /// Where the song was when `sampledAt` was taken. Writing it is how Doni tells the
    /// lyrics screen that time has passed.
    public var progress: TimeInterval = 0 {
        didSet { sampledAt = .now }
    }

    /// Bumped on every seek. The lyrics screen uses it to tell a user's jump from the
    /// song simply moving along.
    public var seekRevision = 0

    /// The rate the song is moving at, in song-seconds per real second.
    public var rate: Double = 0

    /// Called when a lyric line is tapped and the song should move to it.
    public var onSeek: ((TimeInterval) -> Void)?

    @ObservationIgnored private var sampledAt = Date()

    public init() {}

    /// Where the song is at `date`, including the part of the interval between two of
    /// Doni's ticks that has already gone by. Asked for constantly, so it has to be
    /// arithmetic rather than a published value.
    public func estimatedProgress(at date: Date = .now) -> TimeInterval {
        guard isPlaying, rate > 0 else { return progress }
        return progress + date.timeIntervalSince(sampledAt) * rate
    }

    public func seek(to time: TimeInterval) {
        onSeek?(time)
    }
}
