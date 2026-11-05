import Support
import SwiftUI
import TelegramDesignSystem

/// The reference's row for every song list — search, favourites, playlist, album
/// (`TrackRowView.swift:17-59`): a 44 pt cover at radius 6, 12 to two lines 3 apart, the name in
/// `.body` and the rest in `.caption` under it, duration in `.caption.monospacedDigit()` trailing and
/// only when the file has one. It never shows play state; the bar at the foot of the screen owns that.
struct MusicTrackRow: View {
    let track: any Playable
    /// The reference's `secondaryMetadata`: one more fact joined onto the artist line with " · "
    /// (`TrackRowView.swift:170-182`, `Localizable.strings:147`). Doni's is the kept slice of the song.
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

    /// A row with nothing under the name is still a two-line row, so "Doni" stands in for the uploader.
    private var subtitle: String {
        let parts = [track.displayPerformer, secondary].compactMap { value in
            let name = value?.trimmedSearchName ?? ""
            return name.isEmpty ? nil : name
        }
        return parts.isEmpty ? "Doni" : parts.joined(separator: " · ")
    }
}
