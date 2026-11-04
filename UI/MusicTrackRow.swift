import Support
import SwiftUI
import TelegramDesignSystem

/// The row the reference puts in front of every song in a list — search, favourites, a playlist, an
/// album (`TrackRowView.swift:17-59`): a 44 pt cover at radius 6, 12 to two lines of text 3 apart,
/// the name in `.body` with everything else about it in `.caption` under it, and the duration in
/// `.caption.monospacedDigit()` at the trailing edge, shown only when the file has a duration at all.
///
/// It says nothing about play state. The reference's row is neutral — what is playing is said by the
/// bar at the foot of the screen, not by the list it came from — so this is the row that replaces the
/// Telegram chat-list row on the screens MeloX owns.
struct MusicTrackRow: View {
    let track: any Playable
    /// The reference's `secondaryMetadata`: one more fact joined onto the artist line with " · "
    /// (`TrackRowView.swift:170-182`, `Localizable.strings:147`). Doni's is the slice of a song that
    /// was kept, which is the one thing this app can say that a streamer's row cannot.
    var secondary: String? = nil
    let artwork: CoverArtwork

    var body: some View {
        HStack(spacing: MusicSearchMetrics.songGap) {
            TrackCover(track: track, side: MusicSearchMetrics.songArt,
                       radius: MusicSearchMetrics.songArtRadius, artwork: artwork)

            VStack(alignment: .leading, spacing: MusicSearchMetrics.songTextGap) {
                Text(track.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: MusicSearchMetrics.songTrailingGap)

            if let text = MediaClock.duration(track.duration) {
                Text(text)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// A row with nothing under the name is still a two-line row, so the app stands in for the
    /// uploader a captionless post never named.
    private var subtitle: String {
        let parts = [track.displayPerformer, secondary].compactMap { value in
            let name = value?.trimmedSearchName ?? ""
            return name.isEmpty ? nil : name
        }
        return parts.isEmpty ? "Doni" : parts.joined(separator: " · ")
    }
}
