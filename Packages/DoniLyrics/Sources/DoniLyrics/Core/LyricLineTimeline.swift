import Foundation

/// The line a song is on, for the surfaces that are not the lyrics screen.
///
/// The lock screen, the Dynamic Island and the media banner all need one fact from the lyrics: which
/// line is being sung right now. Deciding that is not a binary search over the timestamps — it is the
/// same decision the lyrics screen makes, with the same lead the user set, or the island says a line
/// the screen has not reached yet. So this hands out the engine's answer instead of a second copy of
/// it, and the engine stays exactly as the reference wrote it.
public enum LyricLineTimeline {
    /// The line being sung at `time`, `nil` before the first line starts and after the last one ends
    /// is still the last line's turn.
    ///
    /// `settings` is the lyrics screen's own settings, because its advance time is the difference
    /// between a line appearing when it is sung and a line appearing when the file's clock says so —
    /// and that object belongs to the main actor, which is where the screens that show a line are.
    @MainActor
    public static func line(at time: TimeInterval, in lyrics: [LyricLine],
                            settings: AppSettings) -> LyricLine? {
        guard !lyrics.isEmpty else { return nil }
        let adjusted = time + settings.effectiveLyricsAdvanceTime(for: lyrics)
        guard let id = LyricPlaybackTimeline.position(at: adjusted, in: lyrics)
            .highlightedLyricID else { return nil }
        return lyrics.first { $0.id == id }
    }
}
