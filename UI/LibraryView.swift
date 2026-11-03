import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// M2: the library, wearing Telegram's chat-list clothing.
///
/// The chrome is `ChatListItem.swift`'s — a 68 pt row, a 16 pt icon column, the title pinned
/// 8 pt below the top of the row rather than centred, one physical pixel for the rule, and
/// `#e5e5ea` under a finger. What sits in the icon column is `ChatMessageInteractiveFileNode`'s
/// 44 pt play control, because a track is a file, not a peer. Numbers and their lines are in
/// `Docs/design-tokens.md`, "Chat list — the clothing the library wears".
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
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(palette.searchClearButton)
                            .frame(width: TelegramLibraryMetrics.clearWidth, height: TelegramLibraryMetrics.searchFieldHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
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
            }
        }
        .padding(.horizontal, TelegramLibraryMetrics.searchPadding)
        .padding(.top, TelegramLibraryMetrics.searchPadding)
        .padding(.bottom, TelegramLibraryMetrics.searchBelow)
    }

    // MARK: List

    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(indexer.matches(of: query), id: \.uniqueId) { track in
                    TrackRow(
                        track: track,
                        hairline: TelegramGeometry.hairline(displayScale: displayScale),
                        palette: palette,
                        isSelected: indexer.selectedId == track.uniqueId
                    ) {
                        indexer.select(track)
                    }
                }
                footer
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Telegram's list ends in blank white; the count line is Doni's own, and it only exists
    /// while the index is still walking the channel.
    @ViewBuilder
    private var footer: some View {
        if indexer.tracks.isEmpty {
            VStack(spacing: 8) {
                if let failure = indexer.failureLine {
                    Text(failure)
                } else {
                    Text(indexer.isReading ? "Đang đọc kênh…" : "Chưa có bài nào")
                }
            }
            .font(TelegramLibraryTypography.preview)
            .foregroundStyle(palette.chatListMessageText)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else if indexer.isReading {
            Text(indexer.statusLine)
                .font(TelegramLibraryTypography.preview)
                .foregroundStyle(palette.chatListMessageText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}

/// One row. The geometry is the chat list's, down to the title sitting 8 pt from the top
/// instead of centred: `rawContentRect.origin.y = 8`, the preview at `minY + lineHeight − 2`,
/// the timestamp at `minY + 2`.
private struct TrackRow: View {
    let track: TdTrack
    let hairline: CGFloat
    let palette: TelegramPalette
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: TelegramLibraryMetrics.iconToText) {
                PlayBadge(ready: track.isDownloaded, palette: palette)
                    .frame(
                        width: TelegramLibraryMetrics.playDiameter,
                        height: TelegramLibraryMetrics.playDiameter
                    )
                    .padding(.top, TelegramLibraryMetrics.playTop)
                VStack(alignment: .leading, spacing: TelegramLibraryMetrics.titleToPreview) {
                    Text(track.displayTitle)
                        .font(TelegramLibraryTypography.title)
                        .foregroundStyle(palette.chatListTitle)
                        .lineLimit(1)
                    Text(preview)
                        .font(TelegramLibraryTypography.preview)
                        .foregroundStyle(palette.chatListMessageText)
                        .lineLimit(1)
                }
                .padding(.top, TelegramLibraryMetrics.titleTop)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(duration)
                    .font(TelegramLibraryTypography.date)
                    .foregroundStyle(palette.chatListDateText)
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
                        + TelegramLibraryMetrics.playDiameter
                        + TelegramLibraryMetrics.iconToText)
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

    private var duration: String {
        MediaClock.duration(track.duration) ?? "—"
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

/// `progressDiameter`, 44 pt: `mediaActiveControlColor` for what can be played now,
/// `mediaInactiveControlColor` for what still has to come down.
private struct PlayBadge: View {
    let ready: Bool
    let palette: TelegramPalette

    var body: some View {
        ZStack {
            if ready {
                Circle().fill(palette.mediaActiveControl)
                Image(systemName: "play.fill")
                    .font(.system(size: TelegramLibraryMetrics.playGlyph, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: 1)
            } else {
                Circle().stroke(palette.mediaInactiveControl, lineWidth: 2)
                Image(systemName: "arrow.down")
                    .font(.system(size: TelegramLibraryMetrics.downloadGlyph, weight: .semibold))
                    .foregroundStyle(palette.mediaInactiveControl)
            }
        }
    }
}

#Preview {
    LibraryView(session: TelegramSession(), indexer: LibraryIndexer())
}
