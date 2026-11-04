import SwiftUI
import Support
import TelegramDesignSystem
import TdSession
import UIKit

/// The home tab, in MeloX's shape: one screen split by a segmented picker
/// (`HomeView.swift:18-33`, `:36-47`), "Dành cho bạn" over the tiles and the shelves, "Nhạc" over
/// the chips, the hero card and the grid.
///
/// The numbers are the reference's — 32 pt between sections, 8 above the first one and 28 below the
/// last, 16 of gutter, a shelf's own 14 from its title to its cards, 154 pt cards for a song and 166
/// for a playlist at radius 10 (`HomeRecommendedView.swift:101,139-140`,
/// `HomeRecommendationSections.swift:85,102,105,109`, `MediaCardView.swift:8-11`). What fills them is
/// Doni's: there is no recommender behind a Telegram channel, so the tiles are the six things this
/// app can actually do and the shelves are the four groups its store already keeps.
///
/// There is no full-library list at the foot of the feed any more. The songs it showed are the
/// "Tất cả" chip's grid, which reaches them in the same order and lets you see the covers.
struct LibraryView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    /// A tile that opens a screen rather than starting a song asks the shell to move.
    let onOpenTab: (DoniTab) -> Void
    let onOpenPlayer: () -> Void

    @State private var showsAccountMenu = false
    @State private var section: DoniHomeSection = .forYou

    private let palette = TelegramPalette.dark

    /// How many cards a shelf shows before the flick starts. MeloX hands its strips the whole
    /// payload; Doni's library is one channel's thousand songs, so a shelf cuts itself.
    private static let shelfLimit = 20

    /// How many cards a chip's grid holds. The reference asks its category for fifty playlists
    /// (`ExploreView.swift:170`), and fifty covers is what one screen of this can fetch at once.
    private static let facetLimit = 50

    var body: some View {
        VStack(spacing: 0) {
            // The split sits above the content in the reference's own bar: a segmented picker on a
            // strip of the screen's background, sixteen in from the edge (`HomeView.swift:44-47`).
            Picker("Phần", selection: $section) {
                ForEach(DoniHomeSection.allCases) { entry in
                    Text(entry.title).tag(entry)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MusicExploreMetrics.gutter)
            .padding(.vertical, 8)
            .background(palette.chatListBackground)

            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The system's own bar: a large title and three glass circles, which is what MeloX
        // asks for and what iOS 26 draws (`ContentView.swift:377-379`, `:429-460`).
        .navigationTitle("Trang chủ")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: shuffleAll) {
                    Label("Phát ngẫu nhiên", systemImage: "shuffle").labelStyle(.iconOnly)
                }
                Button {
                    indexer.run(session, library: library)
                } label: {
                    Label("Đọc lại kênh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }
                Button {
                    showsAccountMenu = true
                } label: {
                    Label("Kênh và tài khoản", systemImage: "ellipsis").labelStyle(.iconOnly)
                }
            }
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

    // MARK: Sections

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .forYou:
            feed
        case .music:
            HomeBrowse(session: session, player: player, artwork: artwork, facets: facets) {
                await indexer.reload(session, library: library)
            }
        }
    }

    // MARK: Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MusicFeedMetrics.sectionSpacing) {
                // A channel still being read has no tiles worth tapping, so the first screen is the
                // walk's own progress rather than six actions over "0 bài".
                if !visible.isEmpty {
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
                }

                footer(visible.isEmpty, failure: indexer.failureLine)
            }
            .padding(.top, MusicFeedMetrics.feedTop)
            .padding(.bottom, MusicFeedMetrics.feedBottom)
        }
        .animation(TelegramLoginMotion.easeInOut(0.2), value: visible.map(\.uniqueId))
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
                            await artwork.load(track: track, via: session.covers(),
                                               side: MusicFeedMetrics.songCard)
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
                            await artwork.load(track: shelf.cover, via: session.covers(),
                                               side: MusicFeedMetrics.playlistCard)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The chips the "Nhạc" segment has: the groups this store keeps, then the performers that recur
    /// in it. MeloX's chips are Netease's playlist categories (`ExploreView.swift:24-27`); what a
    /// Telegram channel repeats is the nearest thing this app has to a category. Five performers is
    /// where the row stops being browsable, and a song one artist sang once is not an artist chip.
    private var facets: [HomeFacet] {
        var list = [HomeFacet(title: "Tất cả", tracks: cut(visible))]
        if !keptAll.isEmpty {
            list.append(HomeFacet(title: "Yêu thích", tracks: cut(keptAll)))
        }
        if !offlineAll.isEmpty {
            list.append(HomeFacet(title: "Trên máy", tracks: cut(offlineAll)))
        }
        for artist in visible.searchArtists.prefix(5) where artist.tracks.count > 1 {
            list.append(HomeFacet(title: artist.name, tracks: cut(artist.tracks)))
        }
        return list
    }

    private func cut(_ list: [any Playable]) -> [any Playable] {
        Array(list.prefix(Self.facetLimit))
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

    // MARK: While the channel is being read

    /// What the feed says when there is nothing shelved yet, or the read did not finish. It used to
    /// hang under the full-library list; with the list gone it stands on its own, in the same fonts
    /// and greys.
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
