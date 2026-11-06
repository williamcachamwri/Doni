import SwiftUI
import Support
import TelegramDesignSystem

/// The player strip in the tab bar's glass accessory, as MeloX builds it: a 40 pt cover at radius 6,
/// the title in `subheadline.semibold` over the artist in `caption` secondary, then play/pause and next
/// as 36 pt circles — no progress line, which the reference leaves to the panel. A 28 pt flick across
/// the strip skips a track; `MiniPlayerView.swift` measures all of it.
/// The container is the system's, so the strip adds no background. It does watch `placement`, because
/// the reference shrinks the bar when the tab bar minimises — 30 pt cover, one line, no next button
/// (`MiniPlayerView.swift:106-112`).
struct MiniPlayerBar: View {
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    /// The id the panel's cover zooms out of, shared with the shell's transition.
    let transitionID: String
    let namespace: Namespace.ID
    let open: () -> Void

    /// Inline is the minimised bar: less room, so the second line and the third button go.
    private var isInline: Bool { placement == .inline }
    private var spacing: CGFloat {
        isInline ? MusicMiniPlayerMetrics.spacingInline : MusicMiniPlayerMetrics.spacing
    }
    private var artSide: CGFloat {
        isInline ? MusicMiniPlayerMetrics.artInline : MusicMiniPlayerMetrics.art
    }

    var body: some View {
        if let track = player.current {
            HStack(spacing: spacing) {
                opener(track: track)

                transport

                if !isInline {
                    nextButton
                }
            }
            .padding(.horizontal, isInline ? MusicMiniPlayerMetrics.horizontalPaddingInline
                                           : MusicMiniPlayerMetrics.horizontalPadding)
            .padding(.vertical, isInline ? MusicMiniPlayerMetrics.verticalPaddingInline
                                         : MusicMiniPlayerMetrics.verticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .simultaneousGesture(swipe)
            .accessibilityAction(named: "Bài trước") { player.previous() }
            .accessibilityAction(named: "Bài tiếp theo") { player.next() }
        }
    }

    /// Cover and text are one button: everything left of the transport opens the panel.
    private func opener(track: any Playable) -> some View {
        Button(action: open) {
            HStack(spacing: spacing) {
                TrackCover(track: track, side: artSide,
                           radius: MusicMiniPlayerMetrics.artRadius, artwork: artwork)
                    .matchedTransitionSource(id: transitionID, in: namespace)
                VStack(alignment: .leading, spacing: MusicMiniPlayerMetrics.textSpacing) {
                    Text(track.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !isInline {
                        Text(track.displayPerformer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
            .accessibilityLabel(player.isPlaying ? String(localized: "Tạm dừng")
                    : String(localized: "Phát"))
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
}
