import SwiftUI
import Support
import TelegramDesignSystem

/// The strip of player the kit calls the toolbar: a 56 pt card of thick material with a 14 pt
/// continuous corner, a 40 pt artwork inset 8, the title in `semibold(15)` beside it, and
/// `play`/`forward` at 18 pt whose trailing edge sits 2.33 pt inside the card.
/// `AMToolbarView.swift` measures every one of those numbers. Tapping the card is how the
/// player opens; the two buttons are the only other touches it has.
struct MiniPlayerBar: View {
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    /// The artwork morphs into the player's cover, so the strip holds the geometry while the
    /// player is away and hands it over while the player is up.
    let namespace: Namespace.ID
    let isSource: Bool
    let open: () -> Void

    private let palette = TelegramPalette.dark

    var body: some View {
        if let track = player.current {
            HStack(spacing: 8) {
                TrackCover(track: track,
                           side: TelegramShellMetrics.miniPlayerArt,
                           radius: TelegramShellMetrics.miniPlayerArtRadius,
                           artwork: artwork)
                    .matchedGeometryEffect(id: "player-art", in: namespace, isSource: isSource)
                Text(track.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.navPrimaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                controls
            }
            .padding(.leading, 8)
            .padding(.trailing, 2.33)
            .frame(height: TelegramShellMetrics.miniPlayerHeight)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thickMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture(perform: open)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Mở toàn màn hình")
        }
    }

    /// The two bar buttons at the configuration's own 18 pt
    /// (`UIButton.Configuration+Toolbar.swift:12`), plus Doni's download glyph in the play slot
    /// while the file is still being fetched.
    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 0) {
            Button(action: player.toggle) {
                Image(systemName: playSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(palette.navPrimaryText)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Tạm dừng" : "Phát")

            Button(action: player.next) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.navPrimaryText)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tiếp theo")
        }
    }

    private var playSymbol: String {
        if player.isFetchingFile { return "arrow.down" }
        return player.isPlaying ? "pause.fill" : "play.fill"
    }
}
