import SwiftUI
import Support
import TelegramDesignSystem
import TdSession
import UIKit

/// The home tab, wearing MeloX's feed: a row of gradient tiles, then shelves of cards you flick
/// sideways, then the whole library as the list it has always been.
///
/// The numbers are the reference's — 32 pt between sections, 8 above the first one and 28 below the
/// last, 16 of gutter, a shelf's own 14 from its title to its cards, 154 pt cards for a song and 166
/// for a playlist at radius 10 (`HomeRecommendedView.swift:101,139-140`,
/// `HomeRecommendationSections.swift:85,102,105,109`, `MediaCardView.swift:8-11`). What fills them is
/// Doni's: there is no recommender behind a Telegram channel, so the tiles are the six things this
/// app can actually do and the shelves are the four groups its store already keeps.
///
/// The list stays at the foot of the feed because it *is* the library — MeloX's home embeds
/// `LibraryView` as one of its own sections (`HomeView.swift:79-80`), which is the same bargain:
/// the feed on top, the songs under it.
struct LibraryView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    /// A tile that opens a screen rather than starting a song asks the shell to move.
    let onOpenTab: (DoniTab) -> Void
    let onOpenPlayer: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.telegramFloatingClearance) private var floatingClearance

    @State private var showsAccountMenu = false

    private let palette = TelegramPalette.dark

    /// How many cards a shelf shows before the flick starts. MeloX hands its strips the whole
    /// payload; Doni's library is one channel's thousand songs, so a shelf cuts itself.
    private static let shelfLimit = 20

    var body: some View {
        ZStack(alignment: .top) {
            feed
            LargeTitleHeader(title: "Thư viện", actions: [
                HeaderAction(symbol: "shuffle", label: "Phát ngẫu nhiên") {
                    shuffleAll()
                },
                HeaderAction(symbol: "arrow.clockwise", label: "Đọc lại kênh") {
                    indexer.run(session, library: library)
                },
                HeaderAction(symbol: "ellipsis", label: "Kênh và tài khoản") {
                    showsAccountMenu = true
                },
            ])
        }
        .background(palette.chatListBackground.ignoresSafeArea())
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

    // MARK: Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MusicFeedMetrics.sectionSpacing) {
                HomeQuickActions(subtitle: subtitle, perform: perform)

                if !newest.isEmpty {
                    songShelf("Mới nhất", newest)
                }
                if !kept.isEmpty {
                    songShelf("Yêu thích", kept)
                }
                if !offline.isEmpty {
                    songShelf("Trên máy", offline)
                }
                if !playlists.isEmpty {
                    playlistShelf
                }

                allSongs
            }
            .padding(.top, MusicFeedMetrics.feedTop)
            .padding(.bottom, MusicFeedMetrics.feedBottom)
        }
        .contentMargins(.top, TelegramHeaderMetrics.topClearance, for: .scrollContent)
        .contentMargins(.bottom, floatingClearance, for: .scrollContent)
        .refreshable { await indexer.reload(session, library: library) }
    }

    /// A shelf of song cards. Tapping one starts the shelf's own list at that song, which is what
    /// MeloX's `player.play(song, in: songs)` does (`HomeRecommendationSections.swift:44-51`).
    private func songShelf(_ title: String, _ list: [any Playable]) -> some View {
        HomeShelf(title: title, playAll: { play(list) }) {
            ForEach(list, id: \.uniqueId) { track in
                Button {
                    play(list, startingAt: track)
                } label: {
                    HomeCard(cover: track, title: track.displayTitle,
                             subtitle: track.displayPerformer,
                             side: MusicFeedMetrics.songCard, artwork: artwork)
                        .task(id: track.uniqueId) {
                            await artwork.load(track: track, via: session.covers())
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var playlistShelf: some View {
        HomeShelf(title: "Danh sách") {
            ForEach(playlists, id: \.uniqueId) { shelf in
                Button {
                    onOpenTab(.playlists)
                } label: {
                    HomeCard(cover: shelf.cover, title: shelf.name,
                             subtitle: "\(shelf.count) bài",
                             side: MusicFeedMetrics.playlistCard, artwork: artwork)
                        .task(id: shelf.cover.uniqueId) {
                            await artwork.load(track: shelf.cover, via: session.covers())
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The library as it has always been shown: the whole channel's songs, newest first, in rows.
    private var allSongs: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Text("Tất cả bài hát")
                .font(.title2.bold())
                .padding(.horizontal, MusicFeedMetrics.gutter)
                .padding(.bottom, MusicFeedMetrics.headerToShelf)

            ForEach(visible, id: \.uniqueId) { track in
                TrackRow(
                    track: track,
                    query: "",
                    hairline: TelegramGeometry.hairline(displayScale: displayScale),
                    palette: palette,
                    isCurrent: player.current?.uniqueId == track.uniqueId,
                    isPlaying: player.current?.uniqueId == track.uniqueId && player.isPlaying,
                    headline: track.headline,
                    isFavorite: keptIds.contains(track.uniqueId),
                    artwork: artwork
                ) {
                    play(visible, startingAt: track)
                }
                .trackActions(track, library: library)
                .transition(.offset(y: 6).combined(with: .opacity))
                .task(id: track.uniqueId) {
                    await artwork.load(track: track, via: session.covers())
                }
            }
            footer(visible.isEmpty, failure: indexer.failureLine)
        }
        .animation(TelegramLoginMotion.easeInOut(0.2), value: visible.map(\.uniqueId))
    }

    // MARK: Content

    /// The walk's own order — newest message first — which is the order both the list and the
    /// "Mới nhất" shelf read.
    private var visible: [any Playable] {
        indexer.tracks
    }

    private var newest: [any Playable] {
        Array(visible.prefix(Self.shelfLimit))
    }

    private var kept: [any Playable] {
        Array(keptAll.prefix(Self.shelfLimit))
    }

    private var keptAll: [any Playable] {
        library.favorites.map { $0.track }
    }

    private var keptIds: Set<String> {
        Set(keptAll.map(\.uniqueId))
    }

    private var offlineAll: [any Playable] {
        visible.filter { $0.isDownloaded }
    }

    private var offline: [any Playable] {
        Array(offlineAll.prefix(Self.shelfLimit))
    }

    /// A list the user made, and the song whose cover stands in for the artwork MeloX reads off
    /// the network. A list still empty has no cover to wear, so it stays off the shelf.
    private struct PlaylistShelf {
        let name: String
        let count: Int
        let cover: any Playable
        let uniqueId: String
    }

    private var playlists: [PlaylistShelf] {
        library.playlists.prefix(Self.shelfLimit).compactMap { list in
            guard let cover = library.tracks(in: list.id).first else { return nil }
            return PlaylistShelf(name: list.name, count: list.trackCount,
                                 cover: cover, uniqueId: String(list.id))
        }
    }

    // MARK: Tiles

    private func subtitle(_ action: DoniHomeAction) -> String {
        switch action {
        case .shuffle: return "\(visible.count) bài trong kênh"
        case .newest: return "\(newest.count) bài vừa về"
        case .likes: return "\(keptAll.count) bài đã tim"
        case .offline: return "\(offlineAll.count) bài có trên máy"
        case .lists: return "\(library.playlists.count) danh sách của bạn"
        case .resume: return player.current?.displayTitle ?? "Chưa có bài nào đang nghe"
        }
    }

    private func perform(_ action: DoniHomeAction) {
        switch action {
        case .shuffle: shuffleAll()
        case .newest: play(visible)
        case .likes: onOpenTab(.likes)
        case .offline: play(offlineAll)
        case .lists: onOpenTab(.playlists)
        case .resume:
            if player.current != nil {
                onOpenPlayer()
            } else {
                play(visible)
            }
        }
    }

    // MARK: Playback

    /// The shuffle the header's first action runs: the whole library, in an order that is not the
    /// channel's. Telegram's own bar actions are one tap each, so this starts immediately rather
    /// than asking.
    private func shuffleAll() {
        var list = visible
        guard !list.isEmpty else { return }
        list.shuffle()
        player.play(list[0], in: list)
    }

    private func play(_ list: [any Playable]) {
        guard let first = list.first else { return }
        player.play(first, in: list)
    }

    private func play(_ list: [any Playable], startingAt track: any Playable) {
        player.play(track, in: list)
    }

    // MARK: End of the list

    /// Telegram's list ends in blank white, so what the end of this list says is Doni's own —
    /// but it says it in the list's own fonts and greys.
    @ViewBuilder
    private func footer(_ isEmpty: Bool, failure: String?) -> some View {
        if isEmpty {
            if indexer.isReading {
                VStack(spacing: 12) {
                    Spinner(color: palette.navControl, side: 24)
                    Text(indexer.statusLine.isEmpty ? "Đang đọc kênh…" : indexer.statusLine)
                        .font(TelegramLibraryTypography.preview)
                        .foregroundStyle(palette.chatListMessageText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
            } else if let failure {
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
        } else if let failure {
            // Reading can fail into a half-filled library, and the bar no longer has room to say
            // so, so the end of the list does.
            HStack(spacing: 8) {
                Text(failure)
                    .font(TelegramLibraryTypography.preview)
                    .foregroundStyle(palette.chatListDraftText)
                Button("Thử lại") { indexer.run(session, library: library) }
                    .font(TelegramLibraryTypography.preview)
                    .foregroundStyle(palette.highlight)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
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
        library: Library.shared,
        onOpenTab: { _ in },
        onOpenPlayer: {}
    )
}
