import SwiftUI
import TelegramDesignSystem

/// What is behind the full-window player (`DesktopNowPlayingBackground.swift`): black, the cover blown
/// up to 1.35 and blurred to nothing, a 0.10 veil over it, and a top-to-bottom gradient whose three
/// stops exist so white text is readable at the bottom of a bright album.
///
/// The reference offers three background styles and takes two of their numbers from settings; Doni has
/// no settings screen yet, so it ships the one that needs no Metal field — the blurred artwork — with
/// the scale and blur already measured off MeloX for the phone (`MusicNowPlayingMetrics`), so the two
/// shells cannot drift apart on the same song.
struct DesktopNowPlayingBackdrop: View {
    @EnvironmentObject private var artwork: CoverArtwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let track: (any Playable)?
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                backgroundContent(in: proxy.size)
                    .transition(.opacity)

                Color.black.opacity(0.10)

                LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.12),
                                        .black.opacity(0.48)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private func backgroundContent(in size: CGSize) -> some View {
        if let track, let image = artwork.image(for: track, side: 300) {
            Image(doni: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .scaleEffect(MusicNowPlayingMetrics.backdropScale)
                .blur(radius: MusicNowPlayingMetrics.backdropBlur)
                .saturation(0.9)
                .opacity(isActive ? 1 : 0.85)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: track.uniqueId)
        }
    }
}

/// The two buttons that sit where the window's titlebar is (`DesktopNowPlayingWindowControls.swift`):
/// 74 × 36, 26 pt glyphs, white on a clear interactive glass capsule.
struct DesktopNowPlayingWindowControls: View {
    let close: () -> Void
    let openMiniPlayer: (() -> Void)?

    var body: some View {
        HStack(spacing: 9) {
            chromeButton("Thoát trình phát", systemImage: "xmark", action: close)
            if let openMiniPlayer {
                chromeButton("Thu nhỏ", systemImage: "pip.exit", action: openMiniPlayer)
            }
        }
        .frame(width: openMiniPlayer == nil ? 36 : 74, height: 36)
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white)
        .modifier(DesktopNowPlayingGlassCapsule())
    }

    private func chromeButton(_ title: String, systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(LocalizedStringKey(title), systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 26, height: 26)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text(localized(title)))
        .help(title)
    }
}

/// The volume capsule on the player's own titlebar row (`DesktopNowPlayingVolumeControl.swift`): a
/// 130 × 22 slider whose thumb is always shown, one button for mute, all of it white on clear glass.
struct DesktopNowPlayingVolumeControl: View {
    @EnvironmentObject private var player: Player
    @State private var volumeBeforeMute: Float?

    var body: some View {
        HStack(spacing: 1) {
            slider
            Button(action: toggleMute) {
                Label(localized(volumeLabel), systemImage: volumeSymbol)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(localized(volumeLabel)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .modifier(DesktopNowPlayingGlassCapsule())
    }

    @ViewBuilder private var slider: some View {
        if #available(macOS 26.0, *) {
            volumeSlider.sliderThumbVisibility(.visible)
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
        .tint(.white)
        .controlSize(.mini)
        .frame(width: 130, height: 22)
        .contentShape(.rect)
        .accessibilityLabel("Âm lượng")
    }

    private var volumeLabel: String {
        player.volume > 0.001 ? "Tắt tiếng" : "Bật tiếng"
    }

    private var volumeSymbol: String {
        switch player.volume {
        case ...0.001: "speaker.slash.fill"
        case ..<0.35: "speaker.wave.1.fill"
        case ..<0.7: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    private func toggleMute() {
        if let before = volumeBeforeMute {
            player.volume = before
            volumeBeforeMute = nil
        } else {
            volumeBeforeMute = max(player.volume, 0.2)
            player.volume = 0
        }
    }
}
