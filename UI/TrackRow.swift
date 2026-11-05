import SwiftUI
import Support
import TelegramDesignSystem
import UIKit

/// The chat-list row, worn by every list this app shows.
/// The geometry is the chat list's, down to the title sitting 8 pt from the top instead of centred:
/// `rawContentRect.origin.y = floor(base × 8 / 17)` at `base` 17, preview at `minY + lineHeight − 2`,
/// timestamp at `minY + 2`, rule inset to where the text column begins.
struct TrackRow: View {
    let track: any Playable
    let query: String
    let hairline: CGFloat
    let palette: TelegramPalette
    /// The row the player is holding, which wears the list's own `itemSelectedBackgroundColor`.
    let isCurrent: Bool
    let isPlaying: Bool
    /// The right-hand slot's first line. The list rather than the row decides it, because a
    /// favourited slice has a range to show where the library has a duration.
    let headline: String
    /// Doni's own mark — the chat list has no heart in a row. 12 pt at the accent the design lab picked
    /// (`#3e88f7`), small enough beside the 14 pt number not to widen the column.
    let isFavorite: Bool
    let artwork: CoverArtwork
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(alignment: .top, spacing: TelegramLibraryMetrics.artToText) {
                ArtworkTile(
                    track: track,
                    artwork: artwork,
                    hairline: hairline,
                    palette: palette
                )
                    .padding(.top, TelegramLibraryMetrics.artTop)
                VStack(alignment: .leading, spacing: TelegramLibraryMetrics.titleToPreview) {
                    HighlightedText(
                        text: track.displayTitle,
                        query: query,
                        font: TelegramLibraryTypography.title,
                        color: palette.chatListTitle,
                        accent: palette.highlight
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)   // a song's name matters at both ends (`ChatMessageInteractiveFileNode.swift:751`)
                    HighlightedText(
                        text: track.previewLine,
                        query: query,
                        font: TelegramLibraryTypography.preview,
                        color: palette.chatListMessageText,
                        accent: palette.highlight
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .padding(.top, TelegramLibraryMetrics.titleTop)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Two absolute positions rather than a stack with a gap: the reference pins the
                // timestamp to the top of the content rect and the bubble to its *bottom*, so the
                // distance between them is a consequence, not a number (`:4556`, `:4625`).
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: TelegramLibraryMetrics.favoriteMark))
                                .foregroundStyle(palette.highlight)
                        }
                        Text(headline)
                            .font(TelegramLibraryTypography.duration)
                            .foregroundStyle(palette.chatListDateText)
                    }
                    .padding(.top, TelegramLibraryMetrics.dateTop)
                    StateBubble(ready: track.isDownloaded, playing: isPlaying, palette: palette)
                        .padding(.top, TelegramLibraryMetrics.stateTop)
                }
                .frame(height: TelegramLibraryMetrics.rowHeight, alignment: .top)
                .layoutPriority(1)
                .padding(.leading, TelegramLibraryMetrics.minGapToTimestamp)
            }
            .padding(.leading, TelegramLibraryMetrics.leading)
            .padding(.trailing, TelegramLibraryMetrics.trailing)
            .frame(maxWidth: .infinity)
            .frame(height: TelegramLibraryMetrics.rowHeight)
            .background(isCurrent ? palette.chatListItemSelected : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.chatListSeparator)
                    .frame(height: hairline)
                    .padding(.leading, TelegramLibraryMetrics.leading
                        + TelegramLibraryMetrics.artSide
                        + TelegramLibraryMetrics.artToText)
                    .padding(.trailing, TelegramLibraryMetrics.trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ChatListHighlight(color: palette.chatListItemHighlighted))
    }
}

/// The icon column: the sharp cover once TDLib has fetched it, the message's minithumbnail until then,
/// Telegram's avatar gradient when the post has no artwork — always clipped as a rounded square, the
/// shape the reference gives every artwork (`ArtworkImage.swift:7`).
struct ArtworkTile: View {
    let track: any Playable
    let artwork: CoverArtwork
    let hairline: CGFloat
    let palette: TelegramPalette

    private var sharp: UIImage? { artwork.sharp(for: track) }
    private var mini: UIImage? { artwork.mini(for: track) }

    var body: some View {
        ZStack {
            MissingArtwork(side: TelegramLibraryMetrics.artSide)
            if let mini {
                fill(mini)
            }
            if let sharp {
                // The sharp file fades over the soft one it replaces rather than swapping under a
                // scrolling list — the 0.15 s a badge takes to appear (`ChatListBadgeNode.swift:205`).
                fill(sharp)
                    .transition(.opacity)
            }
        }
        .animation(TelegramShellMotion.crossfade, value: sharp != nil)
        .frame(
            width: TelegramLibraryMetrics.artSide,
            height: TelegramLibraryMetrics.artSide
        )
        .clipShape(.rect(cornerRadius: MusicArtworkMetrics.radius))
        .overlay {
            // A pale cover on a black list needs an edge; the list draws its rules one pixel wide.
            RoundedRectangle(cornerRadius: MusicArtworkMetrics.radius)
                .strokeBorder(palette.chatListSeparator, lineWidth: hairline)
        }
    }

    private func fill(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .overlay(Color.black.opacity(TelegramLibraryMetrics.artScrim))
    }
}

/// A finger puts `itemHighlightedBackgroundColor` behind the row, and it leaves over 0.3 s
/// `.easeInEaseOut` while it arrives instantly (`ChatListItem.swift:2156-2162`).
struct ChatListHighlight: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? color : Color.clear)
            .animation(
                configuration.isPressed ? nil : TelegramLoginMotion.easeInOut(0.3),
                value: configuration.isPressed
            )
    }
}

/// The unread-bubble slot: whether a tap plays now or waits, and which row is making noise. In dark the
/// two controls are white, and white at 0.4 with a `#262628` glyph inside
/// (`DefaultDarkPresentationTheme.swift:559`), like Telegram's own play button.
struct StateBubble: View {
    let ready: Bool
    let playing: Bool
    let palette: TelegramPalette

    var body: some View {
        ZStack {
            Circle().fill(ready ? palette.mediaActiveControl : palette.mediaInactiveControl)
            Image(systemName: glyph)
                .font(.system(size: TelegramLibraryMetrics.stateGlyph, weight: .bold))
                .foregroundStyle(palette.mediaControlGlyph)
                .offset(x: glyph == "play.fill" ? 0.5 : 0)
        }
        .frame(
            width: TelegramLibraryMetrics.stateSide,
            height: TelegramLibraryMetrics.stateSide
        )
    }

    private var glyph: String {
        if playing { return "pause.fill" }
        return ready ? "play.fill" : "arrow.down"
    }
}

/// The query, coloured where it matches. The hit comes from `SearchHighlight`, which folds each
/// character the way the matcher does, so a toneless query still lights up the accented title.
struct HighlightedText: View {
    let text: String
    let query: String
    let font: Font
    let color: Color
    let accent: Color

    var body: some View {
        Text(runs).font(font)
    }

    /// The matched runs, carried as attributes rather than built by adding `Text` to `Text`: that
    /// operator is deprecated on iOS 26, and the SDK points at attributed strings instead.
    private var runs: AttributedString {
        var line = AttributedString()
        for segment in SearchHighlight.segments(of: query, in: text) {
            var run = AttributedString(segment.text)
            run.foregroundColor = segment.isMatch ? accent : color
            line.append(run)
        }
        return line
    }
}

/// Telegram's `ActivityIndicator`, in SwiftUI: a trimmed ring that turns for 0.8 s.
struct Spinner: View {
    let color: Color
    var side: CGFloat = 18

    @State private var turned = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(turned ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    turned = true
                }
            }
            .accessibilityHidden(true)
    }
}
