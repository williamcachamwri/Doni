import SwiftUI
import TelegramDesignSystem

/// The five buttons, at the reference's compact sizes (`DesktopPlaybackControls.swift:49-58`): 28, 28,
/// 36, 28, 28 inside a 148-point cluster. The glyph sizes are the measured ones, not a scale of them,
/// because the bar is 54 points tall and every point of that is spoken for.
///
/// Shuffle and repeat are the two rows that *are* state — they light up in the app's red when they are
/// doing something — and that is read live, in the view, which is where a published change is seen.
struct DesktopPlaybackControls: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var player: Player

    var body: some View {
        HStack(spacing: 0) {
            shuffleButton.frame(width: 28, height: 28)
            previousButton.frame(width: 28, height: 28)
            playButton.frame(width: 36, height: 36)
            nextButton.frame(width: 28, height: 28)
            repeatButton.frame(width: 28, height: 28)
        }
        .frame(width: 148, height: 36)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var shuffleButton: some View {
        Button {
            player.setShuffled(!player.isShuffled)
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(player.isShuffled ? MusicTint.accent : .primary.opacity(0.58))
        }
        .help(player.isShuffled ? "Tắt phát ngẫu nhiên" : "Phát ngẫu nhiên")
    }

    private var previousButton: some View {
        Button {
            player.previous()
        } label: {
            Image(systemName: "backward.fill")
                .font(.system(size: 13, weight: .semibold))
        }
        .disabled(!player.hasPrevious)
        .help("Bài trước")
    }

    private var playButton: some View {
        Button {
            player.toggle()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 19, weight: .semibold))
                .contentTransition(
                    .symbolEffect(.replace, options: .speed(DesktopPlayerMotion.playbackSymbolSpeed))
                )
        }
        // The same key the menu registers; SwiftUI resolves the duplicate to one action rather than
        // firing the press twice.
        .keyboardShortcut(DesktopPlaybackKeyboardShortcuts.togglePlayback)
        .help(player.isPlaying ? "Tạm dừng (phím cách)" : "Phát (phím cách)")
    }

    private var nextButton: some View {
        Button {
            player.next()
        } label: {
            Image(systemName: "forward.fill")
                .font(.system(size: 13, weight: .semibold))
        }
        .disabled(!player.hasNext)
        .help("Bài tiếp theo")
    }

    private var repeatButton: some View {
        Button {
            player.cycleRepeatMode()
        } label: {
            Image(systemName: player.repeatSystemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(player.repeatMode == .off ? .primary.opacity(0.58) : MusicTint.accent)
        }
        .help(repeatHelp)
    }

    /// The row names the mode it will move *to*, which is the only way a cycling button can be read
    /// before it is pressed.
    private var repeatHelp: String {
        switch player.repeatMode {
        case .off: return "Lặp lại toàn bộ"
        case .all: return "Lặp lại một bài"
        case .one: return "Không lặp lại"
        }
    }
}

/// The volume control: one speaker glyph that grows a slider out of itself on hover, inside its own
/// piece of glass (`DesktopPlaybackControls.swift:201-340`).
///
/// The glass is `.identity` — no material at all — while collapsed, and `.regular.interactive()` the
/// moment it opens, so the button is part of the bar's own sheet of glass until it becomes a control
/// you can grab.
struct DesktopVolumeControl: View {
    @EnvironmentObject private var player: Player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isExpanded: Bool
    @State private var isVolumeTrackHovered = false
    @State private var volumeBeforeMute: Float?

    var body: some View {
        surfacedControl
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(.capsule)
            .onHover { hovering in
                guard !hovering, isExpanded else { return }
                setExpanded(false)
            }
            .animation(
                reduceMotion ? nil : DesktopPlayerMotion.volume(expanded: isExpanded),
                value: isExpanded
            )
    }

    @ViewBuilder private var surfacedControl: some View {
        if #available(macOS 26.0, *) {
            controlContent.glassEffect(
                isExpanded ? .regular.interactive() : .identity,
                in: .capsule
            )
        } else {
            controlContent.background {
                if isExpanded {
                    Capsule().fill(Color.primary.opacity(0.08))
                }
            }
        }
    }

    private var controlContent: some View {
        HStack(spacing: isExpanded ? 14 : 0) {
            if isExpanded {
                volumeTrack
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                // Collapsed, the button's job is to open; expanded, it is the mute. Doni's player has no
                // mute state of its own, so the value being silenced is held here and given back —
                // jumping to full volume on the second press would be a different promise.
                if !isExpanded {
                    setExpanded(true)
                } else if let before = volumeBeforeMute {
                    player.volume = before
                    volumeBeforeMute = nil
                } else {
                    volumeBeforeMute = player.volume
                    player.volume = 0
                }
            } label: {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Tắt tiếng" : "Hiện âm lượng")
        }
        .padding(.leading, isExpanded ? 10 : 9)
        .padding(.trailing, 9)
        .frame(height: 36)
        .contentShape(.capsule)
    }

    @ViewBuilder private var volumeTrack: some View {
        if #available(macOS 26.0, *) {
            volumeSlider
                .sliderThumbVisibility(isVolumeTrackHovered ? .visible : .hidden)
                .onHover { isVolumeTrackHovered = $0 }
        } else {
            volumeSlider
        }
    }

    private var volumeSlider: some View {
        Slider(
            value: Binding(
                get: { Double(player.volume) },
                set: { player.volume = Float($0) }
            ),
            in: 0...1
        )
        .tint(MusicTint.accent)
        .controlSize(.small)
        .frame(width: 64, height: 18)
        .accessibilityLabel("Âm lượng")
        .help("Âm lượng")
    }

    private var volumeSymbol: String {
        switch player.volume {
        case ...0.001: "speaker.slash.fill"
        case ..<0.35: "speaker.wave.1.fill"
        case ..<0.7: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        withAnimation(reduceMotion ? nil : DesktopPlayerMotion.volume(expanded: expanded)) {
            isExpanded = expanded
        }
    }
}
