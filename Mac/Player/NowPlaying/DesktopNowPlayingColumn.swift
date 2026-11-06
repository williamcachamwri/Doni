import SwiftUI
import TelegramDesignSystem

/// The cover, the way the player column draws it (`DesktopNowPlayingArtwork.swift`): it grows by
/// 1/0.74 while the song plays and shrinks back when it stops, with a bounce on every transition —
/// 1.055 out in 0.17 s, home on a 0.42 spring at 0.24 bounce — and a shadow that deepens with it
/// (0.18/14/8 paused, 0.34/26/15 playing).
///
/// The reference makes the shrink a setting. Doni has no player settings screen yet, so it ships on,
/// which is what the reference does by default; when the settings pane lands this becomes a read
/// rather than a constant.
struct DesktopNowPlayingArtwork: View {
    private static let pausedArtworkScale: CGFloat = 0.74

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let track: (any Playable)?
    let pausedSize: CGFloat
    let isPlaying: Bool

    @State private var bounceScale: CGFloat = 1

    var body: some View {
        Group {
            if let track {
                DesktopArtworkView(track: track, side: pausedSize, cornerRadius: 11)
            } else {
                Color.secondary.opacity(MusicArtworkMetrics.placeholderFill)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: pausedSize, height: pausedSize)
        .scaleEffect(expansionScale * bounceScale)
        .shadow(
            color: .black.opacity(isPlaying ? 0.34 : 0.18),
            radius: isPlaying ? 26 : 14,
            y: isPlaying ? 15 : 8
        )
        .animation(reduceMotion ? nil : .smooth(duration: 0.48), value: isPlaying)
        .accessibilityElement()
        .accessibilityLabel(Text(track.map { localized("Ảnh bìa của “%@”", $0.displayTitle) }
            ?? localized("Ảnh bìa")))
        .task(id: isPlaying) {
            await animateBounce(whenPlaying: isPlaying)
        }
    }

    private var expansionScale: CGFloat {
        isPlaying ? 1 / Self.pausedArtworkScale : 1
    }

    private func animateBounce(whenPlaying: Bool) async {
        bounceScale = 1
        guard whenPlaying, !reduceMotion else { return }
        await Task.yield()
        withAnimation(.easeOut(duration: 0.17)) {
            bounceScale = 1.055
        }
        do {
            try await Task.sleep(for: .milliseconds(170))
        } catch {
            return
        }
        withAnimation(.spring(duration: 0.42, bounce: 0.24)) {
            bounceScale = 1
        }
    }
}

/// The scrub bar of the full-window player (`DesktopNowPlayingProgress.swift`): an 8 pt track that
/// becomes 18 pt while a drag is in progress, on two timing curves the reference measured —
/// 0.25/0.10/0.25/1 over 0.32 s out, 0.20/0.80/0.20/1 over 0.40 s back — and the two clocks below it
/// rolling as digits rather than swapping glyphs.
///
/// The track is drawn; the interaction is a real `Slider` at 0.1% opacity over it, which is what makes
/// it keyboard-operable and VoiceOver-readable while everything on screen is a capsule.
struct DesktopNowPlayingProgress: View {
    private static let idleTrackHeight: CGFloat = 8
    private static let expandedTrackHeight: CGFloat = 18
    private static let expansionAnimation = Animation.timingCurve(
        0.25, 0.10, 0.25, 1, duration: 0.32)
    private static let collapseAnimation = Animation.timingCurve(
        0.20, 0.80, 0.20, 1, duration: 0.40)

    @EnvironmentObject private var player: Player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTrackExpanded = false
    @State private var scrubbedProgress: TimeInterval?
    @State private var inactiveProgress: TimeInterval = 0

    let tint: Color
    let isActive: Bool
    var scale: CGFloat = 1

    private var contentScale: CGFloat { max(scale, 1) }

    var body: some View {
        VStack(spacing: 0) {
            progressSlider

            HStack {
                Text(clock(elapsedSecond))
                    .contentTransition(.numericText(value: Double(elapsedSecond)))
                    .transaction { transaction in
                        guard let numericTextAnimation else { return }
                        transaction.animation = numericTextAnimation
                    }

                Spacer()

                Text("−" + clock(remainingSecond))
                    .contentTransition(.numericText(value: Double(remainingSecond)))
                    .transaction { transaction in
                        guard let numericTextAnimation else { return }
                        transaction.animation = numericTextAnimation
                    }
            }
            .font(.system(size: 10 * contentScale).monospacedDigit())
            .foregroundStyle(tint.opacity(0.82))
            .padding(.top, 3 * contentScale)
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard !active else { return }
            inactiveProgress = player.elapsed
        }
    }

    private var progressSlider: some View {
        ZStack {
            GeometryReader { geometry in
                progressTrack(width: geometry.size.width)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .allowsHitTesting(false)

            hiddenInteractionSlider
                .opacity(0.001)
                .allowsHitTesting(true)
        }
        .frame(height: Self.expandedTrackHeight * contentScale)
        .contentShape(.rect)
    }

    private func progressTrack(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(tint.opacity(0.22))

            Rectangle()
                .fill(tint)
                .frame(width: width * progressFraction)
        }
        .clipShape(.capsule)
        .frame(width: width, height: trackHeight)
    }

    @ViewBuilder private var hiddenInteractionSlider: some View {
        if #available(macOS 26.0, *) {
            interactionSlider.sliderThumbVisibility(.hidden)
        } else {
            interactionSlider
        }
    }

    private var interactionSlider: some View {
        Slider(
            value: Binding(
                get: { displayedProgress },
                set: { value in
                    scrubbedProgress = value
                    player.seek(to: value)
                }
            ),
            in: 0...maximumProgress,
            onEditingChanged: setScrubbing
        )
        .controlSize(.large)
        .accessibilityLabel("Thời gian phát")
        .accessibilityValue("\(clock(elapsedSecond)) / \(clock(totalSecond))")
    }

    /// While the page is not the one on screen the bar holds still at the second it was left at, so a
    /// hidden player does not visibly run ahead of the one the listener is looking at.
    private var displayedProgress: TimeInterval {
        min(max(scrubbedProgress ?? (isActive ? player.elapsed : inactiveProgress), 0),
            max(player.duration, 0))
    }

    private var maximumProgress: TimeInterval { max(player.duration, 1) }

    private var progressFraction: CGFloat {
        guard maximumProgress > 0 else { return 0 }
        return CGFloat(min(max(displayedProgress / maximumProgress, 0), 1))
    }

    private var trackHeight: CGFloat {
        (isTrackExpanded ? Self.expandedTrackHeight : Self.idleTrackHeight) * contentScale
    }

    private var elapsedSecond: Int { max(Int(displayedProgress), 0) }

    private var remainingSecond: Int {
        max(Int(max(player.duration - displayedProgress, 0)), 0)
    }

    private var totalSecond: Int { max(Int(max(player.duration, 0)), 0) }

    private var numericTextAnimation: Animation? {
        guard !reduceMotion, scrubbedProgress != nil else { return nil }
        return .smooth(duration: 0.18)
    }

    private func setScrubbing(_ scrubbing: Bool) {
        if scrubbing {
            scrubbedProgress = displayedProgress
            setTrackExpanded(true)
        } else {
            if let scrubbedProgress {
                player.seek(to: scrubbedProgress)
            }
            scrubbedProgress = nil
            setTrackExpanded(false)
        }
    }

    private func setTrackExpanded(_ expanded: Bool) {
        guard isTrackExpanded != expanded else { return }
        guard !reduceMotion else {
            isTrackExpanded = expanded
            return
        }
        withAnimation(expanded ? Self.expansionAnimation : Self.collapseAnimation) {
            isTrackExpanded = expanded
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The left half of the full-window player: cover, words about the song, the scrub bar, the transport
/// (`DesktopNowPlayingPlayerColumn.swift`). Every distance in it comes from the layout struct, which
/// is the reference's file byte for byte, so the column grows with the window exactly as Music's does.
struct DesktopNowPlayingColumn: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var library: Library

    let layout: DesktopNowPlayingLayout
    let tint: Color
    let isActive: Bool

    var body: some View {
        let elementScale = layout.elementScale

        VStack(alignment: .leading, spacing: 0) {
            DesktopNowPlayingArtwork(track: player.current,
                                     pausedSize: layout.artworkSize,
                                     isPlaying: player.isPlaying)
                .frame(maxWidth: .infinity)
                .padding(.top, layout.artworkTopInset)

            HStack(alignment: .bottom, spacing: 10 * elementScale) {
                metadata(elementScale: elementScale)

                Spacer(minLength: 6 * elementScale)

                favouriteButton(elementScale: elementScale)
                rowMenu(elementScale: elementScale)
            }
            .padding(.top, layout.metadataTopInset)

            DesktopNowPlayingProgress(tint: tint, isActive: isActive, scale: elementScale)
                .padding(.top, 23 * elementScale)

            DesktopNowPlayingControls(prominentWidth: layout.playerWidth,
                                      prominentScale: elementScale)
                .frame(maxWidth: .infinity)
                .padding(.top, 22 * elementScale)

            Spacer()
        }
    }

    private func metadata(elementScale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5 * elementScale) {
            Text(player.current?.displayTitle ?? localized("Chưa phát bài nào."))
                .font(.system(size: 18 * elementScale, weight: .bold))
                .lineLimit(1)
            Text(player.current?.displayPerformer ?? "")
                .font(.system(size: 14 * elementScale, weight: .medium))
                .foregroundStyle(.white.opacity(0.60))
                .lineLimit(1)
        }
    }

    private func favouriteButton(elementScale: CGFloat) -> some View {
        let kept = player.current.map { library.isFavorite($0.uniqueId) } == true

        return Button {
            guard let track = player.current else { return }
            library.toggleFavorite(track)
        } label: {
            Image(systemName: kept ? "heart.fill" : "heart")
                .font(.system(size: 13 * elementScale, weight: .semibold))
                .frame(width: 28 * elementScale, height: 28 * elementScale)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .modifier(DesktopNowPlayingCircularGlass())
        .accessibilityLabel(Text(kept ? localized("Bỏ yêu thích") : localized("Yêu thích")))
    }

    /// The reference's menu here is a NetEase account's worth of verbs. Doni's are the two a song
    /// answers to from anywhere: put it on the machine, and read the words full size.
    private func rowMenu(elementScale: CGFloat) -> some View {
        Menu {
            if let track = player.current {
                if !track.isDownloaded {
                    Button("Tải về máy", systemImage: "arrow.down.circle") {
                        let sound = player, held = track
                        Task { await sound.download(held) }
                    }
                }
                Button("Hàng đợi", systemImage: "list.bullet") {
                    model.ui.toggleInspector(.queue)
                }

                Divider()
                DesktopPlaylistMenuItems(track: track)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13 * elementScale, weight: .semibold))
                .frame(width: 28 * elementScale, height: 28 * elementScale)
                .contentShape(.circle)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(.white)
        .foregroundStyle(.white)
        .modifier(DesktopNowPlayingCircularGlass())
    }
}

/// The transport at full-window size (`DesktopPlaybackControls.swift:28-47`): 28 / 36 / 48 / 36 / 28
/// with the spacers the reference puts between them, every glyph scaled by `elementScale`.
struct DesktopNowPlayingControls: View {
    @EnvironmentObject private var player: Player
    var prominentWidth: CGFloat
    var prominentScale: CGFloat

    private var controlScale: CGFloat { max(prominentScale, 1) }

    var body: some View {
        HStack(spacing: 0) {
            shuffleButton.frame(width: 28 * controlScale)
            Spacer(minLength: 0)
            previousButton.frame(width: 36 * controlScale)
            Spacer(minLength: 0)
            playButton.frame(width: 48 * controlScale)
            Spacer(minLength: 0)
            nextButton.frame(width: 36 * controlScale)
            Spacer(minLength: 0)
            repeatButton.frame(width: 28 * controlScale)
        }
        .frame(width: prominentWidth)
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
    }

    private func glyph(_ name: String, _ size: CGFloat) -> some View {
        Image(systemName: name).font(.system(size: size * controlScale, weight: .semibold))
    }

    private var shuffleButton: some View {
        Button {
            player.setShuffled(!player.isShuffled)
        } label: {
            glyph("shuffle", 16)
                .foregroundStyle(player.isShuffled ? MusicTint.accent : Color.white.opacity(0.58))
        }
        .help("Phát ngẫu nhiên")
    }

    private var previousButton: some View {
        Button {
            player.previous()
        } label: {
            glyph("backward.fill", 24)
        }
        .disabled(!player.hasPrevious)
        .help("Bài trước")
    }

    private var playButton: some View {
        Button {
            player.toggle()
        } label: {
            glyph(player.isPlaying ? "pause.fill" : "play.fill", 30)
                .contentTransition(.symbolEffect(.replace,
                                                 options: .speed(DesktopPlayerMotion
                                                    .playbackSymbolSpeed)))
        }
        .help(player.isPlaying ? "Tạm dừng (phím cách)" : "Phát (phím cách)")
    }

    private var nextButton: some View {
        Button {
            player.next()
        } label: {
            glyph("forward.fill", 24)
        }
        .disabled(!player.hasNext)
        .help("Bài tiếp theo")
    }

    private var repeatButton: some View {
        Button {
            player.cycleRepeatMode()
        } label: {
            glyph(player.repeatSystemImage, 16)
                .foregroundStyle(player.repeatMode == .off
                    ? Color.white.opacity(0.58) : MusicTint.accent)
        }
        .help("Lặp lại")
    }
}
