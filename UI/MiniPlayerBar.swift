import SwiftUI
import Support
import TelegramDesignSystem

/// The strip of player that rides above the tab bar, as MeloX builds it: a 40 pt cover at radius 6,
/// the title in `subheadline.semibold` over the artist in `caption` at secondary, then play/pause and
/// next as 36 pt circles — no progress line, which the reference leaves to the panel. A flick of 28 pt
/// across the strip skips a track. `MiniPlayerView.swift` measures all of it.
///
/// Doni's own part is the vessel: MeloX hangs this row in the iOS 26 tab bar's accessory slot, which
/// iOS 17 has no equivalent of, so it floats as a card on the chrome backdrop instead.
struct MiniPlayerBar: View {
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The artwork morphs into the player's cover, so the strip holds the geometry while the player
    /// is away and hands it over while the player is up.
    let namespace: Namespace.ID
    let isSource: Bool
    let open: () -> Void

    var body: some View {
        if let track = player.current {
            HStack(spacing: MusicMiniPlayerMetrics.spacing) {
                opener(track: track)

                transport

                nextButton
            }
            .padding(.horizontal, MusicMiniPlayerMetrics.horizontalPadding)
            .padding(.vertical, MusicMiniPlayerMetrics.verticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .background { card }
            .simultaneousGesture(swipe)
            .accessibilityAction(named: "Bài trước") { player.previous() }
            .accessibilityAction(named: "Bài tiếp theo") { player.next() }
        }
    }

    /// The cover and the two lines of text are one button: everything left of the transport is the
    /// way into the panel.
    private func opener(track: any Playable) -> some View {
        Button(action: open) {
            HStack(spacing: MusicMiniPlayerMetrics.spacing) {
                TrackCover(track: track,
                           side: MusicMiniPlayerMetrics.art,
                           radius: MusicMiniPlayerMetrics.artRadius,
                           artwork: artwork)
                    .matchedGeometryEffect(id: "player-art", in: namespace, isSource: isSource)
                VStack(alignment: .leading, spacing: MusicMiniPlayerMetrics.textSpacing) {
                    Text(track.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(track.displayPerformer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(track.displayTitle)
        .accessibilityValue(track.displayPerformer)
        .accessibilityHint("Mở toàn màn hình")
    }

    /// Play/pause, or the spinner the reference shows while a file is still being fetched.
    @ViewBuilder
    private var transport: some View {
        if player.isFetchingFile {
            ProgressView()
                .controlSize(.small)
                .frame(width: MusicMiniPlayerMetrics.button, height: MusicMiniPlayerMetrics.button)
        } else {
            Button(action: player.toggle) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(MusicMiniPlayerMetrics.glyph)
                    .contentTransition(glyphSwap)
                    .animation(glyphAnimation, value: player.isPlaying)
                    .frame(width: MusicMiniPlayerMetrics.button, height: MusicMiniPlayerMetrics.button)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Tạm dừng" : "Phát")
        }
    }

    private var nextButton: some View {
        Button(action: player.next) {
            Image(systemName: "forward.fill")
                .font(MusicMiniPlayerMetrics.glyph)
                .frame(width: MusicMiniPlayerMetrics.button, height: MusicMiniPlayerMetrics.button)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bài tiếp theo")
    }

    /// A flick past the reference's 28 pt, and only when it is mostly horizontal, skips a track.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: MusicMiniPlayerMetrics.swipeDistance)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 { player.next() } else { player.previous() }
            }
    }

    /// `.replace.downUp.wholeSymbol` at 1.6× inside a `.snappy(0.2)` (`MiniPlayerView.swift:54-67`);
    /// reduced motion drops both the effect and the animation.
    private var glyphSwap: ContentTransition {
        reduceMotion ? .identity
            : .symbolEffect(.replace.downUp.wholeSymbol, options: .speed(1.6))
    }

    private var glyphAnimation: Animation? {
        reduceMotion ? nil : MusicMotion.symbolSwap
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: MusicMiniPlayerMetrics.cardRadius, style: .continuous)
            .fill(.thickMaterial)
            .shadow(color: .black.opacity(0.2), radius: 10)
    }
}
