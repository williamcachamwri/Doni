import SwiftUI
import TelegramDesignSystem

/// The numbers the collapsed track is compensated by (`DesktopBottomProgressMetrics.swift`): the idle
/// bar is drawn at 2 pt inside a 14 pt strip and scaled down horizontally so the expansion grows out of
/// the same two ends rather than sliding them apart.
enum DesktopBottomProgressMetrics {
    static let collapsedProgressHorizontalScale: CGFloat = 0.985
    static let expandedTrackHeight: CGFloat = 8
    static let idleTrackHeight: CGFloat = 2
    static let interactionStripHeight: CGFloat = 14
}

/// The seek track: a 2 pt capsule that becomes an 8 pt one under the pointer, with a real `Slider`
/// painted at 0.1% opacity over it doing the dragging (`DesktopBottomSeekBar.swift`).
///
/// The hidden slider is not decoration. It is what makes the track VoiceOver-operable and what gives
/// the drag a keyboard, while everything the eye reads is drawn by the two capsules above it.
struct DesktopBottomSeekBar: View {
    @EnvironmentObject private var player: Player
    let isExpanded: Bool
    let isPressed: Bool

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                progressTrack(width: geometry.size.width)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .allowsHitTesting(false)

            hiddenInteractionSlider
                .opacity(0.001)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressTrack(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.primary.opacity(trackOpacity))

            Rectangle()
                .fill(.primary.opacity(fillOpacity))
                .frame(width: width * progressFraction)
        }
        .clipShape(.capsule)
        .frame(width: width, height: trackHeight)
        .scaleEffect(
            x: isExpanded ? 1 : 1 / DesktopBottomProgressMetrics.collapsedProgressHorizontalScale,
            y: isPressed ? 1.14 : 1
        )
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
                get: { min(player.elapsed, max(player.duration, 0)) },
                set: { player.seek(to: $0) }
            ),
            in: 0...max(player.duration, 1)
        )
        .controlSize(.large)
        .accessibilityLabel("Thời gian phát")
    }

    private var progressFraction: CGFloat {
        let duration = max(player.duration, 0)
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(player.elapsed / duration, 0), 1))
    }

    private var trackHeight: CGFloat {
        isExpanded
            ? DesktopBottomProgressMetrics.expandedTrackHeight
            : DesktopBottomProgressMetrics.idleTrackHeight
    }

    private var trackOpacity: Double { isExpanded ? 0.30 : 0.24 }
    private var fillOpacity: Double { isExpanded ? 0.86 : 0.70 }
}

/// The middle of the bar: what is playing, the track that moves it, and the cover that is a door into
/// the full-window player (`DesktopBottomMetadataSlot.swift`).
struct DesktopBottomMetadataSlot: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var library: Library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let track: any Playable

    @State private var isProgressExpanded = false
    @State private var isArtworkHovered = false
    @GestureState private var isProgressPressed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            metadataContent
                .blur(radius: isProgressExpanded ? 7 : 0)
                .allowsHitTesting(!isProgressExpanded)

            progressOverlay
        }
        .frame(height: DesktopBottomPlayerMetrics.outerHeight)
        .contentShape(.rect)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isProgressPressed) { _, pressed, _ in
                    guard isProgressExpanded else { return }
                    pressed = true
                }
        )
        .animation(reduceMotion ? nil : DesktopPlayerMotion.progressPress, value: isProgressPressed)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                // The lower third of the slot is the track's; hovering over the words does not open it,
                // or the line the listener is reading would blur out from under them.
                if isProgressExpanded || location.y >= 38 {
                    setProgressExpanded(true)
                }
            case .ended:
                setProgressExpanded(false)
            }
        }
        // The bar's cover is 36 points and is often the first place a song's art is asked for at all —
        // a listener can play from the queue without ever opening a list that prefetched it.
        .task(id: track.uniqueId) {
            await model.artwork.load(track: track, via: model.session.covers(), side: 36)
        }
    }

    private var metadataContent: some View {
        HStack(spacing: 4) {
            Button {
                model.ui.isNowPlayingPresented = true
            } label: {
                HStack(spacing: 9) {
                    artwork

                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.displayTitle)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Text(track.displayPerformer)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            playerMenu
        }
    }

    /// The cover grows to 1.18 and an expand glyph fades in over it, because it is a door — the
    /// reference's own affordance for "this opens the player" (`DesktopBottomMetadataSlot.swift:127-155`).
    private var artwork: some View {
        ZStack {
            DesktopArtworkView(track: track, side: 36, cornerRadius: 6)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(isArtworkHovered ? 0.32 : 0))

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.36), radius: 2, y: 1)
                .opacity(isArtworkHovered ? 1 : 0)
                .blur(radius: isArtworkHovered ? 0 : 1.8)
                .scaleEffect(isArtworkHovered ? 1 : 0.62)
        }
        .frame(width: 36, height: 36)
        .scaleEffect(isArtworkHovered ? 1.18 : 1)
        .shadow(color: .black.opacity(isArtworkHovered ? 0.26 : 0),
               radius: isArtworkHovered ? 8 : 0, y: isArtworkHovered ? 4 : 0)
        .zIndex(2)
        .onHover(perform: setArtworkHovered)
        .accessibilityAddTraits(.isButton)
    }

    private var progressOverlay: some View {
        VStack(spacing: 4) {
            if isProgressExpanded {
                HStack {
                    Text(clock(player.elapsed))
                    Spacer()
                    Text("−" + clock(max(player.duration - player.elapsed, 0)))
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(height: 15)
                .transition(.blurReplace.combined(with: .scale(0.94, anchor: .bottom)))
            }

            DesktopBottomSeekBar(isExpanded: isProgressExpanded, isPressed: isProgressPressed)
                .frame(height: DesktopBottomProgressMetrics.interactionStripHeight)
                .contentShape(.rect)
        }
        .padding(.bottom, 1)
        .scaleEffect(
            x: isProgressPressed
                ? 1.022
                : isProgressExpanded
                    ? 1
                    : DesktopBottomProgressMetrics.collapsedProgressHorizontalScale,
            y: isProgressPressed ? 1.06 : 1,
            anchor: .bottom
        )
    }

    /// What the bar can do to a song before the panes can: keep it, and put a copy on this machine.
    private var playerMenu: some View {
        let isKept = library.isFavorite(track.uniqueId)
        return Menu {
            Button(isKept ? "Bỏ yêu thích" : "Yêu thích",
                   systemImage: isKept ? "star.fill" : "star") {
                library.toggleFavorite(track)
            }
            if !track.isDownloaded {
                Button("Tải về máy", systemImage: "arrow.down.circle") {
                    let sound = player, held = track
                    Task { await sound.download(held) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func setArtworkHovered(_ hovered: Bool) {
        guard isArtworkHovered != hovered else { return }
        withAnimation(reduceMotion ? nil
            : hovered ? DesktopPlayerMotion.artworkHover : DesktopPlayerMotion.artworkRest) {
            isArtworkHovered = hovered
        }
    }

    private func setProgressExpanded(_ expanded: Bool) {
        guard isProgressExpanded != expanded else { return }
        withAnimation(reduceMotion ? nil : DesktopPlayerMotion.progress(expanded: expanded)) {
            isProgressExpanded = expanded
        }
    }

    private func clock(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let seconds = max(Int(time), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
