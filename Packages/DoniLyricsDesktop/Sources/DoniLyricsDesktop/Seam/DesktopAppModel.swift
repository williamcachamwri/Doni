import DoniLyrics
import Foundation
import Observation
import SwiftUI

/// The one seam between the reference's desktop lyrics column and Doni's own state.
///
/// `MeloXDesktop` hands its views a single app model, and the copied column reads
/// `model.player`, `model.lyrics`, `model.settings` and `model.currentLyricsFocusID`
/// from it. Doni already owns all four facts — `PlayerStore` mirrors the player,
/// `AppSettings` is the shared lyrics settings, and the parsed lines come from the
/// library's lyric providers — so this type only *points at* them. It stores no lyric
/// of its own, which is the point: a song parsed once is a song read by both shells.
///
/// The reference's own model carries the whole desktop app (library, playback, network).
/// Only the four members the lyrics column touches are reproduced here, because anything
/// more would be a second source of truth for something Doni already decides.
@MainActor
@Observable
public final class DesktopAppModel {
    /// Where the song is, in the reference's own shape: it answers progress from the last
    /// position it was told plus the time since, rather than being re-told every frame.
    public var player: PlayerStore

    /// The words of the song being played.
    public var lyrics: DesktopLyricsModel

    /// The shared lyrics settings, so a change made on the phone is a change the desktop
    /// column reads without anything being copied over.
    public var settings: AppSettings

    /// The line the column opens on. The reference resolves it once here rather than
    /// letting the outer player chrome observe progress and rebuild every tick.
    public var currentLyricsFocusID: LyricLine.ID?

    /// No default values: a default argument is evaluated off the main actor even for a `@MainActor`
    /// type, and both `AppSettings` and `PlayerStore` may only be built on it.
    public init(player: PlayerStore,
                lyrics: DesktopLyricsModel,
                settings: AppSettings) {
        self.player = player
        self.lyrics = lyrics
        self.settings = settings
    }
}

/// The words, as the copied column asks for them.
///
/// `MeloXDesktop` keeps these on its own lyrics store; Doni keeps them on `Lyrics`, which
/// both shells already share. This is the shape the column speaks, filled from that one
/// source — `songID` is Doni's durable track identity, which is what the column uses to
/// decide the words changed.
@MainActor
@Observable
public final class DesktopLyricsModel {
    public var lyrics: [LyricLine] = []
    public var isLoading = false
    public var errorMessage: String?
    public var songID: String?

    public init() {}
}
