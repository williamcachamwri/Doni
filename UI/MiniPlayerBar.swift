import SwiftUI
import Support
import TelegramDesignSystem

/// The strip of player that floats above the tab bar — Telegram's own
/// `OverlayAudioPlayerControlsNode` collapsed to the one thing a list needs: what is playing, how
/// far through it you are, and a finger-stop.
///
/// What is measured is the panel's (`Docs/design-tokens.md`, "Tab bar and the mini player"): 46 pt
/// artwork with a 10 pt corner, `semibold(17)` over `regular(15)`, and the 2 pt progress line,
/// which is Doni's own because the reference keeps its scrubber in the 190 pt expanded panel. That
/// it is a *capsule* rather than a full-bleed band is Doni's own too, because the shell's chrome
/// floats in this build; the inset it uses is therefore the capsule's 12 pt, not the panel's 16.
/// Tapping the strip is the way back to that panel.
struct MiniPlayerBar: View {
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    /// Opening the strip is the only gesture it has; the button inside it is the second.
    let open: () -> Void

    private let palette = TelegramPalette.dark

    var body: some View {
        if let track = player.current {
            ZStack(alignment: .bottom) {
                HStack(spacing: 12) {
                    TrackCover(track: track,
                               side: TelegramShellMetrics.miniPlayerArt,
                               radius: TelegramShellMetrics.miniPlayerArtRadius,
                               artwork: artwork)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.displayTitle)
                            .font(TelegramShellTypography.title)
                            .foregroundStyle(palette.navPrimaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(track.displayPerformer.isEmpty ? track.previewLine
                                                            : track.displayPerformer)
                            .font(TelegramShellTypography.artist)
                            .foregroundStyle(palette.navSecondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    control
                }
                .padding(.horizontal, TelegramShellMetrics.miniPlayerFloatInset)
                .frame(height: TelegramShellMetrics.miniPlayerHeight)
                .contentShape(Capsule())
                .onTapGesture(perform: open)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Mở toàn màn hình")

                progress
            }
            .clipShape(Capsule())
            .telegramGlass(.capsule, fallback: palette.barBlurredBackground)
        }
    }

    /// The state glyph of the row, at the size a bar's button wants. Telegram's own bar glyph is a
    /// bundled asset, so the point size is Doni's own.
    @ViewBuilder
    private var control: some View {
        Button(action: player.toggle) {
            if player.isFetchingFile {
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.navSecondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.navPrimaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying ? "Tạm dừng" : "Phát")
    }

    /// Two physical points of accent along the bottom edge, and the only thing here that moves:
    /// the tick is a quarter second, so the fill is animated for exactly that long to run without
    /// steps.
    private var progress: some View {
        GeometryReader { edge in
            let total = max(player.duration, 1)
            let filled = min(max(player.elapsed / total, 0), 1)
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(palette.navSeparator)
                Rectangle()
                    .fill(palette.highlight)
                    .frame(width: edge.size.width * filled)
                    .animation(.linear(duration: 0.25), value: player.elapsed)
            }
        }
        .frame(height: TelegramShellMetrics.progressBarHeight)
    }
}
