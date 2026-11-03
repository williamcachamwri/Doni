import SwiftUI
import Support
import TelegramDesignSystem
import TdSession
import UIKit

/// M2: the library, wearing Telegram's chat-list clothing.
///
/// The chrome is `ChatListItem.swift`'s — a 68 pt row, the icon column 16 pt from the edge and
/// the text pinned at 84 whatever stands in that column, the title 8 pt below the top of the row
/// rather than centred, one physical pixel for the rule, and `#e5e5ea` under a finger. What
/// stands in the icon column is the track's own cover, which TDLib sends inline with the message
/// (`audio.album_cover_minithumbnail`), and the unread-bubble slot on the right carries whether
/// the file is already on the phone. Numbers and their lines are in `Docs/design-tokens.md`,
/// "Chat list — the clothing the library wears".
struct LibraryView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer

    @Environment(\.displayScale) private var displayScale

    @State private var query = ""
    @State private var showsAccountMenu = false
    @FocusState private var fieldFocused: Bool

    private let palette = TelegramPalette.day

    var body: some View {
        VStack(spacing: 0) {
            header
            rows
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .task { indexer.run(session) }
        .confirmationDialog(
            "Tài khoản",
            isPresented: $showsAccountMenu,
            titleVisibility: .visible
        ) {
            if indexer.isReading {
                Button("Dừng đọc kênh", role: .destructive) { indexer.stop() }
            } else {
                Button("Tải lại thư viện") { indexer.run(session) }
            }
            Button("Đăng xuất", role: .destructive) { session.logOut() }
            Button("Huỷ", role: .cancel) {}
        }
    }

    // MARK: Chrome

    /// The bar is Telegram's blurred material flattened to `opaqueBackgroundColor`; the
    /// search pill is `.modern`, 36 tall with 10 pt of padding, and the rule closing the band
    /// is the bar's own `separatorNode`.
    private var header: some View {
        VStack(spacing: 0) {
            titleRow
                .frame(height: TelegramLibraryMetrics.navigationBarHeight)
            searchRow
        }
        .background(palette.navOpaqueBackground.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.navSeparator)
                .frame(height: TelegramGeometry.hairline(displayScale: displayScale))
        }
    }

    private var titleRow: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("Thư viện")
                    .font(TelegramLibraryTypography.barTitle)
                    .foregroundStyle(palette.navPrimaryText)
                subtitle
            }
            HStack {
                Spacer()
                Button {
                    showsAccountMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(palette.navControl)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
        }
    }

    /// `ChatTitleView`'s second line, `regular(13)` in `secondaryTextColor` — here it is the
    /// channel's name and the indexing count rather than "online", because that is the
    /// information the list needs while it fills.
    private var subtitle: some View {
        Group {
            if indexer.isReading {
                Text(indexer.statusLine)
                    .contentTransition(.numericText())
            } else if let failure = indexer.failureLine {
                Text(failure)
            } else if let channel = indexer.channel {
                Text("@\(channel.username)")
            } else {
                EmptyView()
            }
        }
        .font(TelegramLibraryTypography.barSubtitle)
        .foregroundStyle(palette.navSecondaryText)
        .lineLimit(1)
        .animation(TelegramLoginMotion.easeInOut(0.2), value: indexer.statusLine)
    }

    private var searchRow: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: TelegramLibraryMetrics.searchCornerRadius)
                    .fill(palette.searchInputFill)
                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: TelegramLibraryMetrics.loupeSide, weight: .regular))
                        .foregroundStyle(palette.searchPlaceholder)
                        .frame(width: TelegramLibraryMetrics.loupeSide)
                    if query.isEmpty {
                        Text("Tìm kiếm bài hát")
                            .font(TelegramLibraryTypography.searchField)
                            .foregroundStyle(palette.searchPlaceholder)
                    }
                }
                .padding(.leading, TelegramLibraryMetrics.loupeInset)
                .allowsHitTesting(false)
                TextField("", text: $query)
                    .font(TelegramLibraryTypography.searchField)
                    .foregroundStyle(palette.navPrimaryText)
                    .focused($fieldFocused)
                    .padding(.leading, TelegramLibraryMetrics.fieldTextInset)
                    .padding(.trailing, query.isEmpty
                        ? TelegramLibraryMetrics.searchPadding
                        : TelegramLibraryMetrics.clearWidth)
                    .submitLabel(.done)
                clearButton
            }
            .frame(height: TelegramLibraryMetrics.searchFieldHeight)

            if fieldFocused {
                Button("Huỷ") {
                    query = ""
                    fieldFocused = false
                }
                .font(TelegramLibraryTypography.searchField)   // Cancel without a custom title is `regular(17)`
                .foregroundStyle(palette.accent)
                .padding(.leading, 11)
                .transition(.opacity)
            }
        }
        .animation(TelegramLoginMotion.easeInOut(0.2), value: fieldFocused)
        .padding(.horizontal, TelegramLibraryMetrics.searchPadding)
        .padding(.top, TelegramLibraryMetrics.searchPadding)
        .padding(.bottom, TelegramLibraryMetrics.searchBelow)
    }

    /// The clear button does not fade, it scales: 0.2 hidden, 1.0 shown (`:1647`).
    private var clearButton: some View {
        Button {
            query = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(palette.searchClearButton)
                .frame(width: TelegramLibraryMetrics.clearWidth,
                       height: TelegramLibraryMetrics.searchFieldHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .scaleEffect(query.isEmpty ? TelegramLibraryMetrics.clearHiddenScale : 1.0)
        .opacity(query.isEmpty ? 0 : 1)
        .animation(TelegramLoginMotion.easeInOut(0.2), value: query.isEmpty)
        .allowsHitTesting(!query.isEmpty)
    }

    // MARK: List

    private var rows: some View {
        let visible = indexer.matches(of: query)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topId)
                    ForEach(visible, id: \.uniqueId) { track in
                        TrackRow(
                            track: track,
                            query: query,
                            hairline: TelegramGeometry.hairline(displayScale: displayScale),
                            palette: palette,
                            isSelected: indexer.selectedId == track.uniqueId,
                            artwork: ArtworkCache.image(for: track)
                        ) {
                            indexer.select(track)
                        }
                        .transition(.offset(y: 6).combined(with: .opacity))
                    }
                    footer(visible)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await indexer.reload(session) }
            .animation(TelegramLoginMotion.easeInOut(0.2), value: visible.map(\.uniqueId))
            .onChange(of: query) { _, next in
                guard !next.isEmpty else { return }
                proxy.scrollTo(Self.topId, anchor: .top)
            }
        }
    }

    private static let topId = "library-top"

    /// Telegram's list ends in blank white, so what the end of this list says is Doni's own —
    /// but it says it in the list's own fonts and greys.
    @ViewBuilder
    private func footer(_ visible: [TdTrack]) -> some View {
        if indexer.tracks.isEmpty {
            if indexer.isReading {
                VStack(spacing: 12) {
                    Spinner(color: palette.navControl, side: 24)
                    Text(indexer.statusLine.isEmpty ? "Đang đọc kênh…" : indexer.statusLine)
                        .font(TelegramLibraryTypography.preview)
                        .foregroundStyle(palette.chatListMessageText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
            } else if let failure = indexer.failureLine {
                VStack(spacing: 14) {
                    Text(failure)
                        .font(TelegramLibraryTypography.preview)
                        .foregroundStyle(palette.chatListMessageText)
                        .multilineTextAlignment(.center)
                    Button("Thử lại") { indexer.run(session) }
                        .font(TelegramLibraryTypography.barTitle)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 40)
                        .background(Capsule().fill(palette.accent))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
                .padding(.horizontal, 40)
            } else {
                Text("Chưa có bài nào trong kênh")
                    .font(TelegramLibraryTypography.preview)
                    .foregroundStyle(palette.chatListMessageText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 72)
            }
        } else if visible.isEmpty {
            Text("Không tìm thấy “\(query)”")
                .font(TelegramLibraryTypography.preview)
                .foregroundStyle(palette.chatListMessageText)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if indexer.isReading {
            HStack(spacing: 8) {
                Spinner(color: palette.navControl)
                Text(indexer.statusLine)
            }
            .font(TelegramLibraryTypography.preview)
            .foregroundStyle(palette.chatListMessageText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

/// One row. The geometry is the chat list's, down to the title sitting 8 pt from the top
/// instead of centred: `rawContentRect.origin.y = 8`, the preview at `minY + lineHeight − 2`,
/// the timestamp at `minY + 2`, and the rule inset to where the text column begins.
private struct TrackRow: View {
    let track: TdTrack
    let query: String
    let hairline: CGFloat
    let palette: TelegramPalette
    let isSelected: Bool
    let artwork: UIImage?
    let select: () -> Void

    var body: some View {
        Button(action: select) {
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
                        accent: palette.accent
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)   // a song's name matters at both ends (`ChatMessageInteractiveFileNode.swift:751`)
                    HighlightedText(
                        text: preview,
                        query: query,
                        font: TelegramLibraryTypography.preview,
                        color: palette.chatListMessageText,
                        accent: palette.accent
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .padding(.top, TelegramLibraryMetrics.titleTop)
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 7) {
                    Text(headline)
                        .font(TelegramLibraryTypography.duration)
                        .foregroundStyle(palette.chatListDateText)
                    StateBubble(ready: track.isDownloaded, palette: palette)
                }
                .layoutPriority(1)
                .padding(.top, TelegramLibraryMetrics.dateTop)
                .padding(.leading, TelegramLibraryMetrics.minGapToTimestamp)
            }
            .padding(.leading, TelegramLibraryMetrics.leading)
            .padding(.trailing, TelegramLibraryMetrics.trailing)
            .frame(maxWidth: .infinity)
            .frame(height: TelegramLibraryMetrics.rowHeight)
            .background(isSelected ? palette.chatListItemSelected : Color.clear)
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

    /// Telegram's preview line is "author: message"; the author half of a track is who sang it,
    /// and the size belongs where a channel's message count would not be read.
    private var preview: String {
        let performer = track.displayPerformer
        let size = DataSize.string(track.size)
        if performer.isEmpty {
            return track.origin == .document ? track.fileExtension.uppercased() + " · " + size : size
        }
        return performer + " · " + size
    }

    /// A document has no duration in the schema, and its extension is the useful number there.
    private var headline: String {
        if let seconds = MediaClock.duration(track.duration) { return seconds }
        let ext = track.fileExtension.uppercased()
        return ext.isEmpty ? "—" : ext
    }
}

/// The icon column: real cover art when the message carried it, Telegram's avatar gradient when
/// it did not, always clipped as a `.roundedRect` so the column reads as one shape.
private struct ArtworkTile: View {
    let track: TdTrack
    let artwork: UIImage?
    let hairline: CGFloat
    let palette: TelegramPalette

    var body: some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(Color.black.opacity(TelegramLibraryMetrics.artScrim))
            } else {
                TelegramTrackGradient.linear(track.messageId)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: TelegramLibraryMetrics.artGlyph, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
        .frame(
            width: TelegramLibraryMetrics.artSide,
            height: TelegramLibraryMetrics.artSide
        )
        .clipShape(
            RoundedRectangle(cornerRadius: TelegramLibraryMetrics.artRadius, style: .continuous)
        )
        .overlay {
            // A pale cover on a white list needs an edge; the list already draws its rules one
            // physical pixel wide.
            RoundedRectangle(cornerRadius: TelegramLibraryMetrics.artRadius, style: .continuous)
                .strokeBorder(palette.chatListSeparator, lineWidth: hairline)
        }
    }
}

/// A finger puts `itemHighlightedBackgroundColor` behind the row, and it leaves over 0.3 s
/// `.easeInEaseOut` while it arrives instantly (`ChatListItem.swift:2156-2162`).
private struct ChatListHighlight: ButtonStyle {
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

/// The unread-bubble slot, telling the user whether tapping plays now or waits.
/// `mediaActiveControlColor` for what is on the phone, `mediaInactiveControlColor` for what
/// still has to come down (`DefaultDayPresentationTheme.swift:632-633`).
private struct StateBubble: View {
    let ready: Bool
    let palette: TelegramPalette

    var body: some View {
        ZStack {
            Circle().fill(ready ? palette.mediaActiveControl : palette.mediaInactiveControl)
            Image(systemName: ready ? "play.fill" : "arrow.down")
                .font(.system(size: TelegramLibraryMetrics.stateGlyph, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: ready ? 0.5 : 0)
        }
        .frame(
            width: TelegramLibraryMetrics.stateSide,
            height: TelegramLibraryMetrics.stateSide
        )
    }
}

/// The query, coloured where it matches. Telegram paints the matched text of a search in its
/// accent colour; the hit is found through `SearchHighlight`, which folds each character the
/// same way the matcher does, so a toneless query still lights up the accented title.
private struct HighlightedText: View {
    let text: String
    let query: String
    let font: Font
    let color: Color
    let accent: Color

    var body: some View {
        runs.font(font)
    }

    private var runs: Text {
        let segments = SearchHighlight.segments(of: query, in: text)
        guard segments.count > 1 else {
            return Text(text).foregroundColor(color)
        }
        var result = Text(verbatim: "")
        for segment in segments {
            result = result + Text(verbatim: segment.text)
                .foregroundColor(segment.isMatch ? accent : color)
        }
        return result
    }
}

/// Telegram's `ActivityIndicator`, in SwiftUI: a trimmed ring that turns for 0.8 s.
private struct Spinner: View {
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

/// Decoded cover art, kept for the session. A `minithumbnail` is a few hundred bytes, so the
/// whole library costs well under a megabyte of RAM and a row never re-decodes on scroll.
@MainActor
private enum ArtworkCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let box = NSCache<NSString, UIImage>()
        box.countLimit = 600
        return box
    }()

    static func image(for track: TdTrack) -> UIImage? {
        guard let data = track.miniArtwork else { return nil }
        let key = track.uniqueId as NSString
        if let held = cache.object(forKey: key) { return held }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

#Preview {
    LibraryView(session: TelegramSession(), indexer: LibraryIndexer())
}
