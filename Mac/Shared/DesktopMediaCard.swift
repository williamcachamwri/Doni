import Support
import SwiftUI
import TelegramDesignSystem

/// Where a card's picture comes from. The reference passes a URL because NetEase serves one; Doni's
/// three sources are a cached cover, a file the listener chose, and nothing at all — which is why the
/// card takes a picture rather than a location.
enum DesktopCardArtwork {
    case track(any Playable)
    case image(DoniImage?)
    case glyph(String)
}

/// A media card, at the reference's measurements (`DesktopMediaCard.swift`): a square cover with a
/// 1.018 scale and a deepening shadow under the pointer, a 42-point red play disc that grows out of the
/// bottom-right corner, and a 14pt title over a 12pt secondary line.
struct DesktopMediaCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let subtitle: String?
    let artwork: DesktopCardArtwork
    var cornerRadius: CGFloat = 9
    var action: () -> Void
    var playAction: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Button(action: action) {
                    surface
                        .aspectRatio(1, contentMode: .fit)
                        .scaleEffect(isHovered ? 1.018 : 1)
                        .shadow(
                            color: .black.opacity(isHovered ? 0.20 : 0.08),
                            radius: isHovered ? 12 : 4,
                            y: isHovered ? 6 : 2
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(title)

                if let playAction, isHovered {
                    Button(action: playAction) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(MusicTint.accent, in: .circle)
                            .shadow(radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .help(localized("Phát “%@”", title))
                    .transition(.scale.combined(with: .opacity))
                }
            }

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil
                : .snappy(duration: 0.24, extraBounce: 0.08)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder private var surface: some View {
        switch artwork {
        case let .track(track):
            DesktopArtworkView(track: track, cornerRadius: cornerRadius)
        case let .image(image):
            if let image {
                Image(doni: image)
                    .resizable()
                    .scaledToFill()
                    .background(Color.secondary.opacity(MusicArtworkMetrics.placeholderFill))
                    .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            } else {
                glyph("music.note")
            }
        case let .glyph(name):
            glyph(name)
        }
    }

    private func glyph(_ name: String) -> some View {
        ZStack {
            Color.secondary.opacity(MusicArtworkMetrics.placeholderFill)
            Image(systemName: name)
                .font(MusicArtworkMetrics.placeholderGlyph)
                .foregroundStyle(.tertiary)
        }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
