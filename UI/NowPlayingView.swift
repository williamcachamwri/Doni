import SwiftUI
import MediaPlayer
import Support
import TelegramDesignSystem

/// The full player the strip opens, drawn to the mockup the user pointed at — the Apple Music
/// panel — element for element: a grabber at the top, the cover filling the width less 2 × 16,
/// the words at the left with a star and an ellipsis in round glass buttons at the right, a 4 pt
/// progress line with elapsed and *remaining* times (the cut, when one is being marked, takes the
/// centre slot), three transport buttons, a thumbless system volume between two speakers, and the
/// mockup's three grey glyphs along the bottom.
///
/// Telegram has no such screen — it expands its 190 pt panel in place
/// (`OverlayAudioPlayerControlsNode.swift:806`) — so the layout is the mockup's while the motion
/// is Telegram's: the 0.15 s crossfade (`TelegramShellMotion`) on every track change, the badge
/// node's `pop` easing on the play/pause glyph and the timestamps, a spring press-scale on every
/// button, the symbols swapping with `replace.downUp`, and the song's own words sliding up from
/// the bottom on a change. The screen closes like the panel it imitates: a drag down, or a tap on
/// the grabber.
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
        ZStack {
            backdrop
            GeometryReader { edge in
                VStack(spacing: 0) {
                    grabber
                        .padding(.top, 8)
                    art(edge.size.width - 32)
                        .padding(.top, 12)
                    Spacer(minLength: 24)
                    words
                    scrubber
                        .padding(.top, 20)
                    transport
                        .padding(.top, 16)
                    volume
                        .padding(.top, 20)
                    bottomRow
                        .padding(.top, 24)
                }
                .padding(.bottom, 12)
                .animation(TelegramShellMotion.pop, value: player.current?.uniqueId)
            }
        }
        .preferredColorScheme(.dark)
    }

    /// The cover drawn twice: once as the screen itself — blurred hard, scaled to hide the blur's
    /// edge, dimmed so white text always wins — and once as the square the mockup puts in the
    /// middle. A track with no artwork blurs its own gradient, so even a photoless song tints the
    /// screen the way the mockup's backdrop tints it. Both crossfade on the 0.15 s Telegram easing
    /// when the song changes.
    private var backdrop: some View {
        ZStack {
            if let track = player.current {
                Group {
                    if let image = artwork.image(for: track) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        TelegramTrackGradient.linear(track.messageId)
                    }
                }
                .blur(radius: 64)
                .scaleEffect(1.25)
                .overlay(Color.black.opacity(0.45))
            } else {
                palette.chatListBackground
            }
        }
        .ignoresSafeArea()
        .animation(TelegramShellMotion.crossfade, value: player.current?.uniqueId)
    }

    /// The mockup's only chrome: a drag handle. Tapping it closes, the way a sheet's handle does.
    private var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.35))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .accessibilityLabel("Đóng")
    }

    /// The mockup's art: the width the screen has less 2 × 16, with a soft drop so the square
    /// lifts off its own blurred copy behind it.
    private func art(_ width: CGFloat) -> some View {
        Group {
            if let track = player.current {
                TrackCover(track: track, side: width, radius: 12, artwork: artwork)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.glassFallback)
            }
        }
        .frame(width: width, height: width)
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
        .animation(TelegramShellMotion.crossfade, value: player.current?.uniqueId)
    }

    /// The words at the left, the star and the cut at the right, all on one row — the mockup's
    /// own arrangement. The cut lives in a menu because the mockup's transport has no room for a
    /// fourth button, and a cut is a three-step choice (start, end, keep, or let go), which a menu
    /// states better than a toggle does.
    @ViewBuilder
    private var words: some View {
        if let track = player.current {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayTitle)
                        .font(TelegramShellTypography.playingTitle)
                        .foregroundStyle(palette.navPrimaryText)
                        .lineLimit(2)
                    Text(track.displayPerformer.isEmpty ? "Doni" : track.displayPerformer)
                        .font(TelegramShellTypography.playingArtist)
                        .foregroundStyle(palette.navSecondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                favoriteButton(track)
                cutMenu
            }
            .padding(.horizontal, 16)
            .id(track.uniqueId)
            .transition(.push(from: .bottom))
        }
    }

    /// The mockup's star: white outline while a song is only playing, filled once it is kept.
    private func favoriteButton(_ track: any Playable) -> some View {
        let kept = library.favorites.contains { $0.id == track.uniqueId }
        return Button {
            library.toggleFavorite(track)
        } label: {
            Image(systemName: kept ? "star.fill" : "star")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.navPrimaryText)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(PlayerButtonStyle())
        .telegramGlass(.circle, fallback: palette.glassFallback)
        .symbolEffect(.bounce, value: kept)
        .accessibilityLabel(kept ? "Bỏ yêu thích" : "Yêu thích")
    }

    private var cutMenu: some View {
        Menu {
            if let started = markIn {
                Button("Kết thúc cắt tại \(clock(player.elapsed))") {
                    guard player.elapsed > started else { return }
                    player.segment = started...player.elapsed
                    markIn = nil
                }
            } else if player.segment == nil {
                Button("Bắt đầu cắt tại \(clock(player.elapsed))") {
                    markIn = player.elapsed
                }
            }
            if let segment = player.segment {
                Button("Giữ đoạn này") {
                    if let uniqueId = player.current?.uniqueId {
                        library.setSegment(
                            Int(segment.lowerBound)...Int(segment.upperBound),
                            uniqueId: uniqueId)
                    }
                }
                Button("Bỏ cắt", role: .destructive) {
                    player.segment = nil
                    markIn = nil
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(markIn == nil && player.segment == nil
                    ? palette.navPrimaryText : palette.highlight)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .telegramGlass(.circle, fallback: palette.glassFallback)
        .accessibilityLabel("Cắt đoạn")
    }

    /// The mockup's 4 pt line with round caps, in the track's own colours — white over white at
    /// a third. A drag is held locally and handed to the player once, when the finger lifts.
    private var scrubber: some View {
        VStack(spacing: 6) {
            lane
            timestamps
        }
        .padding(.horizontal, 16)
    }

    private var lane: some View {
        GeometryReader { edge in
            let total = max(player.duration, 1)
            let shown = min(max(dragProgress ?? player.elapsed / total, 0), 1)
            let width = max(edge.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.navPrimaryText.opacity(0.3))
                    .frame(width: width, height: 4)
                Capsule()
                    .fill(palette.navPrimaryText)
                    .frame(width: width * shown, height: 4)
                    .animation(.linear(duration: 0.25), value: player.elapsed)
            }
            // 22 pt of band around a 4 pt line: a scrubber you cannot hit is not a scrubber.
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

    /// Elapsed at the left, what is left of the song at the right with its minus sign, the way the
    /// mockup prints it. The centre slot the mockup gives to Dolby Atmos carries the cut instead:
    /// its range while it is held, the moment it starts from while it is being marked. Both times
    /// run on `numericText`, so a second ticks in rather than blinks in.
    private var timestamps: some View {
        HStack {
            Text(MediaClock.duration(Int(player.elapsed.rounded())) ?? "0:00")
            Spacer()
            cutState
            Spacer()
            Text(remaining)
        }
        .font(TelegramShellTypography.timestamp)
        .foregroundStyle(palette.navSecondaryText)
        .monospacedDigit()
        .contentTransition(.numericText())
        .animation(.linear(duration: 0.25), value: player.elapsed)
    }

    /// The centre slot only ever holds text, so the two times stay pinned to their edges whether
    /// or not there is a cut — marking one never moves them under the finger.
    @ViewBuilder
    private var cutState: some View {
        if let segment = player.segment {
            Text("\(clock(segment.lowerBound)) – \(clock(segment.upperBound))")
        } else if let started = markIn {
            Text("cắt từ \(clock(started))")
        }
    }

    private var remaining: String {
        let left = max(Int((player.duration - player.elapsed).rounded()), 0)
        guard let text = MediaClock.duration(left) else { return "-0:00" }
        return "-\(text)"
    }

    /// Three buttons and nothing else: the mockup's transport. The centre glyph swaps through
    /// `replace.downUp` so the pause drops in from above, the way Telegram's own player swaps its
    /// button images in place.
    private var transport: some View {
        HStack(spacing: 0) {
            step(system: "backward.fill", size: 34, enabled: player.hasPrevious,
                 action: player.previous)
            Spacer(minLength: 0)
            step(system: player.isPlaying ? "pause.fill" : "play.fill", size: 46,
                 enabled: player.current != nil, action: player.toggle)
            Spacer(minLength: 0)
            step(system: "forward.fill", size: 34, enabled: player.hasNext, action: player.next)
        }
        .padding(.horizontal, 60)
    }

    /// The system volume, wearing the mockup's own clothes: a speaker at each end and the slider
    /// between them. `MPVolumeView` is the one public way to move the device's volume from an app;
    /// its thumb is erased so the slider reads as the mockup's bare line.
    private var volume: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.navSecondaryText)
            SystemVolumeSlider()
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.navPrimaryText)
        }
        .padding(.horizontal, 16)
    }

    /// The mockup's three resting glyphs along the bottom. Doni has no lyrics, AirPlay screen or
    /// queue screen behind them yet, so they sit as the mockup draws them — grey, at rest.
    private var bottomRow: some View {
        HStack(spacing: 0) {
            Image(systemName: "quote.bubble")
                .frame(maxWidth: .infinity)
            Image(systemName: "airplayaudio")
                .frame(maxWidth: .infinity)
            Image(systemName: "list.bullet")
                .frame(maxWidth: .infinity)
        }
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(palette.navSecondaryText.opacity(0.7))
        .padding(.horizontal, 36)
    }

    private func step(system: String, size: CGFloat, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(enabled ? palette.navPrimaryText
                                         : palette.navSecondaryText.opacity(0.5))
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerButtonStyle())
        .disabled(!enabled)
    }

    private func clock(_ seconds: Double) -> String {
        MediaClock.duration(Int(seconds.rounded())) ?? "0:00"
    }
}

/// Telegram's press state: the button dips to 0.82 on a spring that overshoots a little on the
/// way back up, the way `ChatListBadgeNode`'s own scale eases.
struct PlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// `MPVolumeView` worn to match the mockup: the route button hidden, the thumb erased, white ink
/// on a third-white track — found by walking the view's own tree once it has laid out.
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.tintColor = .white
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        Task { Self.dress(view) }
    }

    private static func dress(_ root: UIView) {
        for subview in root.subviews {
            if let slider = subview as? UISlider {
                slider.minimumTrackTintColor = .white
                slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
                for state: UIControl.State in [.normal, .selected, .highlighted] {
                    slider.setThumbImage(UIImage(), for: state)
                }
            } else if let button = subview as? UIButton {
                // The route button is deprecated but still drawn by default; hiding it here is
                // the panel's own decision, the mockup's volume row has no route button.
                button.isHidden = true
            } else {
                dress(subview)
            }
        }
    }
}
