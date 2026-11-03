import SwiftUI
import Support
import TelegramDesignSystem

/// The full player the strip opens.
///
/// The reference has no such screen — Telegram expands its 190 pt panel in place
/// (`OverlayAudioPlayerControlsNode.swift:806`) — so the layout is Doni's while the numbers are
/// still the ones in `Docs/design-tokens.md`: the art's 10 pt corner, the bar's `semibold(17)` and
/// `regular(15)`, `medium(12)` timestamps, a 7 pt round-capped scrubber in the reference's own
/// colours, and 64 pt buttons. The two glyph sizes and the 360 pt art cap are marked Doni's own.
struct NowPlayingView: View {
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork

    @Environment(\.dismiss) private var dismiss

    /// Where the finger is holding the scrubber, which is not where the song is.
    @GestureState private var dragProgress: Double?

    private let palette = TelegramPalette.dark

    var body: some View {
        GeometryReader { edge in
            VStack(spacing: 0) {
                closeButton
                    .frame(height: TelegramLibraryMetrics.navigationBarHeight)
                Spacer(minLength: 24)
                art(edge.size.width)
                Spacer(minLength: 24)
                words
                scrubber
                    .padding(.top, 22)
                transport
                    .padding(.top, 14)
                Spacer(minLength: 8)
            }
            .padding(.bottom, 20)
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    /// Art takes the width the phone has, less the shell's own inset, and stops at 360: a cover
    /// stretched across a Max is a blurry square, not a record sleeve.
    private func art(_ width: CGFloat) -> some View {
        let side = min(width - 2 * TelegramShellMetrics.miniPlayerSideInset, 360)
        return Group {
            if let track = player.current {
                TrackCover(track: track,
                           side: side,
                           radius: TelegramShellMetrics.miniPlayerArtRadius,
                           artwork: artwork)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(TelegramShellMotion.crossfade, value: player.current?.uniqueId)
    }

    private var closeButton: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.navControl)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng")
            Spacer()
            Text("Đang phát")
                .font(TelegramLibraryTypography.barTitle)
                .foregroundStyle(palette.navPrimaryText)
            Spacer()
            // The bar's own symmetry: the title sits centred because both slots exist.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 4)
    }

    private var words: some View {
        Group {
            if let track = player.current {
                VStack(spacing: 2) {
                    Text(track.displayTitle)
                        .font(TelegramShellTypography.title)
                        .foregroundStyle(palette.navPrimaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(track.displayPerformer.isEmpty ? "Doni" : track.displayPerformer)
                        .font(TelegramShellTypography.artist)
                        .foregroundStyle(palette.navSecondaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, TelegramShellMetrics.miniPlayerSideInset)
            }
        }
    }

    /// `scrubberThickness = 7.0` with round caps, the fill in `itemPrimaryTextColor` over a track
    /// of `controlSecondaryColor` at half (`:266`, `:716`). A drag is held locally and handed to
    /// the player once, when the finger lifts — seeking on every change would fight the tick.
    private var scrubber: some View {
        VStack(spacing: 6) {
            lane
            timestamps
        }
        .padding(.horizontal, TelegramShellMetrics.miniPlayerSideInset)
    }

    private var lane: some View {
        GeometryReader { edge in
            let total = max(player.duration, 1)
            let shown = min(max(dragProgress ?? player.elapsed / total, 0), 1)
            let width = max(edge.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.navSecondaryText.opacity(0.5))
                    .frame(width: width, height: TelegramShellMetrics.scrubberHeight)
                Capsule()
                    .fill(palette.navPrimaryText)
                    .frame(width: width * shown, height: TelegramShellMetrics.scrubberHeight)
                    .animation(.linear(duration: 0.25), value: player.elapsed)
            }
            // 22 pt of band around a 7 pt line: a scrubber you cannot hit is not a scrubber.
            .frame(width: edge.size.width, height: edge.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragProgress) { value, state, _ in
                        state = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        player.seek(to: min(max(value.location.x / width, 0), 1) * total)
                    }
            )
        }
        .frame(height: 22)
    }

    private var timestamps: some View {
        HStack {
            Text(MediaClock.duration(Int(player.elapsed.rounded())) ?? "0:00")
            Spacer()
            Text(MediaClock.duration(Int(player.duration.rounded())) ?? "0:00")
        }
        .font(TelegramShellTypography.timestamp)
        .foregroundStyle(palette.navSecondaryText)
        .monospacedDigit()
    }

    /// 64 pt of touch area, the way the reference sizes its transport buttons (`:887`). Its glyphs
    /// are bundled assets in a 76 pt box (`:899`), so the point sizes here are Doni's own.
    private var transport: some View {
        HStack(spacing: 0) {
            Spacer()
            step(system: "backward.fill", size: 26, enabled: player.hasPrevious, action: player.previous)
            Spacer()
            step(system: player.isPlaying ? "pause.fill" : "play.fill", size: 40,
                 enabled: true, action: player.toggle)
            Spacer()
            step(system: "forward.fill", size: 26, enabled: player.hasNext, action: player.next)
            Spacer()
        }
        .padding(.horizontal, TelegramShellMetrics.miniPlayerSideInset)
    }

    private func step(system: String, size: CGFloat, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(enabled ? palette.navPrimaryText : palette.navSecondaryText.opacity(0.5))
                .frame(width: TelegramShellMetrics.transportButton,
                       height: TelegramShellMetrics.transportButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
