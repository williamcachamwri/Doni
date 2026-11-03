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
    @ObservedObject var library: Library

    @Environment(\.dismiss) private var dismiss

    /// Where the finger is holding the scrubber, which is not where the song is.
    @GestureState private var dragProgress: Double?
    /// The start of a cut the user is marking, before they have reached its end.
    @State private var markIn: Double?

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
                sliceCaption
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
            // 26 pt of band around a 7 pt line — the height the reference gives the scrubber, not
            // the thickness of the line (`:867`): a scrubber you cannot hit is not a scrubber.
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
        .frame(height: TelegramShellMetrics.scrubberBand)
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

    /// 64 pt of touch area, the way the reference sizes its transport buttons (`:887`), spread
    /// across the 320 pt band its three centre buttons keep (`:888`) with a side slot on each flank
    /// (`:891`, `:892`). The reference's flanks are an order button and a looping one; Doni keeps
    /// the loop and spends the other slot on a heart. The glyph sizes are Doni's own — the
    /// reference's are bundled assets in a 76 pt box (`:899`).
    private var transport: some View {
        HStack(spacing: 0) {
            if let track = player.current {
                keepButton(track)
            } else {
                Color.clear
                    .frame(width: TelegramShellMetrics.transportButton,
                           height: TelegramShellMetrics.transportButton)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                step(system: "backward.fill", size: 26, enabled: player.hasPrevious,
                     action: player.previous)
                Spacer(minLength: 0)
                step(system: player.isPlaying ? "pause.fill" : "play.fill", size: 40,
                     enabled: true, action: player.toggle)
                Spacer(minLength: 0)
                step(system: "forward.fill", size: 26, enabled: player.hasNext, action: player.next)
            }
            .frame(maxWidth: TelegramShellMetrics.transportCentreBand)
            Spacer(minLength: 0)
            loopButton
        }
        .padding(.leading, TelegramShellMetrics.transportSlotInset)
        .padding(.trailing, TelegramShellMetrics.transportSlotInset)
    }

    private func keepButton(_ track: any Playable) -> some View {
        let kept = library.favorites.contains { $0.id == track.uniqueId }
        return Button {
            library.toggleFavorite(track)
        } label: {
            Image(systemName: kept ? "heart.fill" : "heart")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(kept ? palette.highlight : palette.navPrimaryText)
                .frame(width: TelegramShellMetrics.transportButton,
                       height: TelegramShellMetrics.transportButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kept ? "Bỏ yêu thích" : "Yêu thích")
    }

    /// The loop, which here is a cut: press it at the start of the part worth keeping, press it
    /// again at the end, and the player holds itself inside that while the song plays. A third
    /// press lets go of it.
    private var loopButton: some View {
        let looping = player.segment != nil
        return Button(action: mark) {
            Image(systemName: looping ? "repeat.1.fill" : (markIn == nil ? "repeat" : "repeat.1"))
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(looping || markIn != nil
                    ? palette.highlight : palette.navPrimaryText)
                .frame(width: TelegramShellMetrics.transportButton,
                       height: TelegramShellMetrics.transportButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cắt đoạn")
    }

    private func mark() {
        if player.segment != nil {
            player.segment = nil
            markIn = nil
            return
        }
        guard let started = markIn else {
            markIn = player.elapsed
            return
        }
        guard player.elapsed > started else { return }
        player.segment = started...player.elapsed
        markIn = nil
    }

    /// What the cut currently is, said in the panel's own `medium(12)` (`:267`), with the button
    /// that writes it down beside it. The height is held whether or not there is a cut, so marking
    /// one never moves the transport under the finger.
    @ViewBuilder
    private var sliceCaption: some View {
        VStack(spacing: 0) {
            if let segment = player.segment {
                HStack(spacing: 10) {
                    Text("\(clock(segment.lowerBound)) – \(clock(segment.upperBound))")
                        .foregroundStyle(palette.navSecondaryText)
                    keepSliceButton(segment)
                }
            } else if let started = markIn {
                Text("Cắt từ \(clock(started)) · nhấn ⟳ để dừng cắt")
                    .foregroundStyle(palette.navSecondaryText)
            }
        }
        .font(TelegramShellTypography.timestamp)
        .monospacedDigit()
        .frame(height: TelegramShellMetrics.sliceCaptionHeight)
        .padding(.top, 8)
    }

    /// `setFavoriteSegment` writes onto a heart that already exists, so this never has to know
    /// whether the song was kept whole first.
    private func keepSliceButton(_ segment: ClosedRange<Double>) -> some View {
        let uniqueId = player.current?.uniqueId ?? ""
        let kept = library.favorites.first { $0.id == uniqueId }?.segment
            == Int(segment.lowerBound)...Int(segment.upperBound)
        return Button(kept ? "Bỏ cắt" : "Giữ đoạn") {
            library.setSegment(kept ? nil : Int(segment.lowerBound)...Int(segment.upperBound),
                               uniqueId: uniqueId)
        }
        .font(TelegramShellTypography.timestamp)
        .foregroundStyle(kept ? palette.navSecondaryText : palette.highlight)
    }

    private func clock(_ seconds: Double) -> String {
        MediaClock.duration(Int(seconds.rounded())) ?? "0:00"
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
