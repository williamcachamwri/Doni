import SwiftUI
import Support
import TelegramDesignSystem
import TdSession
import UIKit

/// M2: the library, wearing Telegram's chat-list clothing, in the mode the whole shell is
/// measured in — dark, true black, one hairline colour from the bar to the rules.
///
/// The chrome is `ChatListUI`'s — a 68 pt row, the icon column 16 pt from the edge and the text
/// pinned at 84 whatever stands in that column, the title 8 pt below the top of the row rather
/// than centred, one physical pixel for the rule, and `#121212` under a finger
/// (`DefaultDarkPresentationTheme.swift:484`). What stands in the icon column is the track's own
/// cover: the sharp 600×600 file Telegram already holds on the server when it has one
/// (`external_album_covers`), the 40×30 `minithumbnail` the message carried when it does not, and
/// the avatar gradient when there is no artwork at all. A tap hands the track to `Player`.
/// Numbers and their lines are in `Docs/design-tokens.md`.
struct LibraryView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.displayScale) private var displayScale

    @State private var query = ""
    @State private var showsAccountMenu = false
    /// The strip of player is the closed state of this; opening it is the strip's only job.
    @State private var showsPlayer = false
    @FocusState private var fieldFocused: Bool

    private let palette = TelegramPalette.dark

    var body: some View {
        VStack(spacing: 0) {
            header
            rows
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerBar(player: player, artwork: artwork) { showsPlayer = true }
                .transition(.offset(y: TelegramShellMetrics.miniPlayerHeight)
                    .combined(with: .opacity))
        }
        .fullScreenCover(isPresented: $showsPlayer) {
            NowPlayingView(player: player, artwork: artwork)
        }
        .animation(TelegramShellMotion.appear, value: player.current?.uniqueId)
        .task {
            player.bind(session.covers())
            indexer.run(session, library: library)
        }
        .confirmationDialog(
            "Tài khoản",
            isPresented: $showsAccountMenu,
            titleVisibility: .visible
        ) {
            if indexer.isReading {
                Button("Dừng đọc kênh", role: .destructive) { indexer.stop() }
            } else {
                Button("Tải lại thư viện") { indexer.run(session, library: library) }
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
                            isCurrent: player.current?.uniqueId == track.uniqueId,
                            isPlaying: player.current?.uniqueId == track.uniqueId && player.isPlaying,
                            artwork: artwork
                        ) {
                            player.play(track, in: Array(visible))
                        }
                        .transition(.offset(y: 6).combined(with: .opacity))
                        .task(id: track.uniqueId) {
                            await artwork.load(track: track, via: session.covers())
                        }
                    }
                    footer(visible)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await indexer.reload(session, library: library) }
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
    private func footer(_ visible: [any Playable]) -> some View {
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
                    Button("Thử lại") { indexer.run(session, library: library) }
                        .font(TelegramLibraryTypography.barTitle)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 40)
                        .background(Capsule().fill(palette.highlight))
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

#Preview {
    LibraryView(
        session: TelegramSession(),
        indexer: LibraryIndexer(),
        player: Player(),
        artwork: CoverArtwork.shared,
        library: Library.shared
    )
}
