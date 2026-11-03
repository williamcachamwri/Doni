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

    private let palette = TelegramPalette.dark

    var body: some View {
        VStack(spacing: 0) {
            header
            rows
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .playerStrip(player: player, artwork: artwork)
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
            SearchField(query: $query, placeholder: "Tìm kiếm bài hát")
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

    // MARK: List

    private var rows: some View {
        let visible = indexer.matches(of: query)
        // The hearts are read off the published list rather than queried per row: a keystroke
        // redraws every visible row, and a thousand lookups for it is a lot of SQL for a screen.
        let kept = Set(library.favorites.map { $0.track.uniqueId })
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
                            headline: track.headline,
                            isFavorite: kept.contains(track.uniqueId),
                            artwork: artwork
                        ) {
                            player.play(track, in: Array(visible))
                        }
                        .contextMenu {
                            Button {
                                library.toggleFavorite(track)
                            } label: {
                                Label(kept.contains(track.uniqueId) ? "Bỏ yêu thích" : "Yêu thích",
                                      systemImage: kept.contains(track.uniqueId)
                                          ? "heart.slash" : "heart")
                            }
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
