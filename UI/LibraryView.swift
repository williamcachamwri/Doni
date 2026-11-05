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

    @State private var showsSettings = false
    @State private var showsAddChannel = false
    @State private var section: DoniHomeSection = .forYou

    private let palette = TelegramPalette.dark

    /// The feed's three verbs, under the title rather than in the bar's status row: shuffle the
    /// library, stop or restart the walk, and open the account's settings.
    ///
    /// The first two were the reference's glass circles in the top bar, and they still are — except
    /// that row belongs to the Dynamic Island while a song is playing, which is precisely when the
    /// home tab gets used. The avatar stays a bare round photo, the way the bar showed it.
    private var headerActions: some View {
        HeaderActionRow {
            Button(action: shuffleAll) {
                Image(systemName: "shuffle")
                    .font(.title2.weight(.semibold))
                    .frame(width: MusicNowPlayingMetrics.headerGlyph, height: MusicNowPlayingMetrics.headerGlyph)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .accessibilityLabel("Phát ngẫu nhiên")

            Button {
                if indexer.isReading {
                    indexer.stop()
                } else {
                    indexer.run(session, library: library)
                }
            } label: {
                Image(systemName: indexer.isReading ? "stop.fill" : "arrow.clockwise")
                    .font(.title2.weight(.semibold))
                    .frame(width: MusicNowPlayingMetrics.headerGlyph, height: MusicNowPlayingMetrics.headerGlyph)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .accessibilityLabel(indexer.isReading ? "Dừng đọc kênh" : "Đọc lại kênh")

            Button {
                showsSettings = true
            } label: {
                AccountAvatar(account: session.account, photo: session.accountPhoto)
                    .frame(width: MusicNowPlayingMetrics.headerGlyph, height: MusicNowPlayingMetrics.headerGlyph)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .accessibilityLabel(session.account.map { "Cài đặt của \($0.name)" } ?? "Cài đặt")
        }
    }

    /// How many cards a shelf shows before the flick starts. MeloX hands its strips the whole
    /// payload; Doni's library is one channel's thousand songs, so a shelf cuts itself.
    private static let shelfLimit = 20

    /// How many cards a chip's grid holds. The reference asks its category for fifty playlists
    /// (`ExploreView.swift:170`), and fifty covers is what one screen of this can fetch at once.
    private static let facetLimit = 50

    var body: some View {
        VStack(spacing: 0) {
            headerActions

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
        // A playlist card on a shelf pushes the detail on this tab's own stack, which is the only way
        // the zoom can carry the cover across it (`AppNavigation.swift:243-248`).
        .navigationDestination(for: Int64.self) { id in
            PlaylistDetailView(playlistId: id, session: session, player: player,
                               artwork: artwork, library: library)
                .musicNavigationTransition(playlistID: id)
        }
        .navigationDestination(isPresented: $showsSettings) {
            SettingsView(session: session, indexer: indexer, player: player, library: library)
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .task {
            player.bind(session.covers())
            // The bind comes first: the restored song may need TDLib for its file, and a player
            // without a downloader would leave the row spinning.
            player.restore()
            // Before the walk rather than after it: the files this needs are already on the phone, so
            // the timestamps land while the channel is still being read.
            await library.measureStoredDurations()
            indexer.run(session, library: library)
            // The first screen's worth of covers, ordered before its cards are drawn. A card asks
            // when it appears, which is a round trip paid while the user is still looking at the
            // gap; queued here they go through the cache's pool six at a time, so the shelves fill
            // over one fetch's latency rather than fifty of them.
            artwork.prefetch(cut(visible), via: session.covers(),
                             side: MusicFeedMetrics.songCard)
            // Behind the walk: this is the slowest thing on the way in — a fetch per row — and the
            // list has nothing to wait for, since each answer lands in its own row as it arrives.
            if let files = session.covers() {
                await library.measureRemoteDurations(with: files)
            }
        }
        .sheet(isPresented: $showsAddChannel) {
            AddChannelSheet(session: session, library: library) {
                indexer.run(session, library: library)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .forYou:
            feed
        case .music:
            HomeBrowse(session: session, player: player, artwork: artwork, facets: facets,
                       addChannel: { showsAddChannel = true }) {
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

                footer(visible.isEmpty, failure: library.storeFailure ?? indexer.failureLine)
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

    /// A list, opened the way the reference opens one: the card hands its cover to the screen the zoom
    /// grows (`MusicNavigationTransitions.swift:43-52`, `AppNavigation.swift:243-248`).
    ///
    /// The card also asks for the hero's size rather than its own, which is MeloX's prefetch on the
    /// source (`MusicNavigationTransitions.swift:48-52, 65-68`): by the time the zoom is running, the
    /// 300 pt picture the detail draws is already on the phone, so the cover that flies out is the
    /// cover that lands.
    private var playlistShelf: some View {
        HomeShelf(title: "Danh sách") {
            ForEach(playlists, id: \.id) { shelf in
                NavigationLink(value: shelf.id) {
                    HomeCard(cover: shelf.cover, title: shelf.name,
                             subtitle: "\(shelf.count) bài",
                             side: MusicFeedMetrics.playlistCard, artwork: artwork)
                        .task(id: shelf.cover.uniqueId) {
                            await artwork.load(track: shelf.cover, via: session.covers(),
                                               side: MusicArtworkMetrics.heroSide)
                        }
                }
                .buttonStyle(.plain)
                .musicMatchedTransitionSource(playlistID: shelf.id)
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
        // One chip for every group the allow-list holds, in the order they were added. "Tất cả"
        // mixes the channels into one river, and someone who joined three of them came here to hear
        // one of them.
        for channel in library.channels where channel.isIndexed {
            let songs = cut(visible.filter { $0.chatId == channel.chatId })
            if songs.count > 1 { list.append(HomeFacet(title: channel.title, tracks: songs)) }
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
        let id: Int64
        let name: String
        let count: Int
        let cover: any Playable
    }

    private var playlists: [PlaylistShelf] {
        library.playlists.prefix(Self.shelfLimit).compactMap { list in
            guard let cover = library.tracks(in: list.id).first else { return nil }
            return PlaylistShelf(id: list.id, name: list.name, count: list.trackCount,
                                 cover: cover)
        }
    }

    // MARK: Tiles

    private func subtitle(_ action: DoniHomeAction) -> String {
        switch action {
        case .shuffle: return "\(visible.count) bài trong thư viện"
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
                // Nothing on the allow-list and a channel that holds no audio are two ways of ending
                // up with an empty feed, and both are answered by the same screen — the one that
                // picks a chat. It is a button, because that is the only thing this screen can do.
                AddChannelPrompt(library.channels.isEmpty
                                 ? "Chưa có kênh nhạc nào"
                                 : "Chưa có bài nào trong kênh") {
                    showsAddChannel = true
                }
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

/// The account's own picture, worn wherever an account is named: 28 pt at the head of the bar
/// (`ContentView.swift:487-488`) and 60 pt in the settings card (`SettingsAccountSection.swift:64-76`).
///
/// The picture is the file behind it rather than the thumbnail `getMe` sends inside the user object:
/// the inline JPEG is around a hundred pixels wide and 28 pt on a 3× screen asks for 84 of them,
/// which is the blur the account's own Telegram does not have. The inline one is what shows first —
/// it arrives with the session and needs no download — and the file replaces it when it lands.
struct AccountAvatar: View {
    let account: TdAccount?
    let photo: UIImage?
    /// The side the mark is drawn at, in points.
    var side: CGFloat = 28

    var body: some View {
        if let photo {
            disc(photo)
        } else if let data = account?.avatarData, let inline = UIImage(data: data) {
            disc(inline)
        } else {
            Image(systemName: account == nil
                ? "person.crop.circle"
                : "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: side, height: side)
        }
    }

    private func disc(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .background(.quaternary, in: .circle)
            .clipShape(.circle)
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
