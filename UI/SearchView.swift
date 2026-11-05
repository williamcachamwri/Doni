import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// Which facet the field is searching. MeloX has five because Netease serves five kinds of result
/// (`SearchView.swift:56-60`, `:145-212`); Doni has the three its own store can answer for.
enum DoniSearchScope: String, CaseIterable, Identifiable {
    case songs
    case playlists
    case artists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs: return "Bài hát"
        case .playlists: return "Danh sách"
        case .artists: return "Nghệ sĩ"
        }
    }
}

/// The search tab, worn the way the reference wears it (`SearchView.swift:25-111`).
/// The chrome is all the system's: `.navigationTitle`, a `.searchable` field in the nav drawer and
/// `.searchScopes` for the facets. Because this tab carries `role: .search`, iOS 26 puts the field in
/// the tab bar's own search circle, opens the keyboard the moment the tab is tapped and shrinks the bar
/// as results scroll; an empty field shows the discovery view (`SearchDiscoveryView.swift:16-45`).
/// No `.searchSuggestions`: MeloX needs them because it waits 350 ms on a network
/// (`SearchView.swift:113-126`), while Doni's index already holds the rows — a suggestion list would
/// cover the results with a text-only copy of them.
struct SearchView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var query = ""
    @State private var scope: DoniSearchScope = .songs

    /// How many of a result set's covers are worth ordering before anyone looks. The rows ask for
    /// themselves too; the point here is that this batch outlives a keystroke.
    private static let coverWarm = 40

    var body: some View {
        Group {
            if trimmed.isEmpty {
                SearchDiscoveryView(session: session, indexer: indexer, artwork: artwork,
                                    library: library, artists: allArtists, search: search)
            } else {
                results
            }
        }
        .navigationDestination(for: Int64.self) { id in
            PlaylistDetailView(playlistId: id, session: session, player: player,
                               artwork: artwork, library: library)
                .musicNavigationTransition(playlistID: id)
        }
        .navigationTitle("Tìm kiếm")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm bài hát")
        .searchScopes($scope) {
            ForEach(DoniSearchScope.allCases) { kind in
                Text(LocalizedStringKey(kind.title)).tag(kind)
            }
        }
        .overlay {
            if !trimmed.isEmpty && isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var trimmed: String { query.trimmedSearchName }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        switch scope {
        case .songs: songResults
        case .playlists: playlistResults
        case .artists: artistResults
        }
    }

    /// MeloX's song list: plain rows, each one a button that plays inside the result set, with the
    /// favourite on a trailing swipe (`SearchView.swift:146-167`).
    private var songResults: some View {
        List {
            ForEach(songMatches, id: \.uniqueId) { track in
                Button {
                    player.play(track, in: songMatches)
                } label: {
                    MusicTrackRow(track: track, artwork: artwork)
                        .task(id: track.uniqueId) {
                            await artwork.load(track: track, via: session.covers(),
                                               side: MusicSearchMetrics.songArt)
                        }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button {
                        library.toggleFavorite(track)
                    } label: {
                        Label(library.isFavorite(track.uniqueId) ? "Bỏ yêu thích" : "Yêu thích",
                              systemImage: library.isFavorite(track.uniqueId) ? "heart.slash" : "heart")
                    }
                    .tint(MusicSearchMetrics.favoriteInk)
                }
            }
        }
        .listStyle(.plain)
        // The result set prefetches through the cache's pool rather than per-row `.task`s: every
        // keystroke rebuilds this list and cancels what the rows had started, so a fast typist never
        // lets one cover finish — the real shape of "it loads but stays blurry for ages". A pool queue
        // belongs to no row and keeps working while the list is retyped under it.
        .task(id: songMatches.prefix(Self.coverWarm).map(\.uniqueId)) {
            artwork.prefetch(Array(songMatches.prefix(Self.coverWarm)),
                             via: session.covers(), side: MusicSearchMetrics.songArt)
        }
    }

    private var playlistResults: some View {
        List {
            ForEach(library.playlists.filter { matches($0.name) }, id: \.id) { list in
                NavigationLink(value: list.id) {
                    SearchMediaRow(title: list.name, subtitle: localized("%@ bài", list.trackCount.formatted())) {
                        PlaylistArt(listId: list.id, coverPath: list.coverPath,
                                    cover: library.firstTrack(in: list.id),
                                    side: MusicSearchMetrics.mediaArt,
                                    radius: MusicSearchMetrics.mediaArtRadius, artwork: artwork)
                            .task(id: list.id) {
                                if let cover = library.firstTrack(in: list.id) {
                                    // The row draws 54 but orders the hero's 300, so the cover the
                                    // zoom flies out is the one the detail draws
                                    // (`MusicNavigationTransitions.swift:48-52, 65-68`).
                                    await artwork.load(track: cover, via: session.covers(),
                                                       side: MusicArtworkMetrics.heroSide)
                                }
                            }
                    }
                }
                .musicMatchedTransitionSource(playlistID: list.id)
            }
        }
        .listStyle(.plain)
    }

    /// An artist has no picture of its own here, so it wears a song it is on. The reference cuts that
    /// to a circle (`SearchView.swift:180-191`, `:394`); this app squares it, because every cover here
    /// is a rounded square.
    private var artistResults: some View {
        List {
            ForEach(artistMatches) { artist in
                Button {
                    search(artist.name)
                } label: {
                    SearchMediaRow(title: artist.name, subtitle: localized("%@ bài", artist.tracks.count.formatted())) {
                        TrackCover(track: artist.sample, side: MusicSearchMetrics.mediaArt,
                                   radius: MusicSearchMetrics.mediaArtRadius, artwork: artwork)
                            .task(id: artist.sample.uniqueId) {
                                await artwork.load(track: artist.sample, via: session.covers(),
                                                   side: MusicSearchMetrics.mediaArt)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Matching

    private var songMatches: [any Playable] {
        guard !trimmed.isEmpty else { return [] }
        switch scope {
        case .songs, .playlists: return indexer.matches(of: query)
        case .artists: return performerMatches
        }
    }

    /// The artists the field names — every artist, folded, before the field says anything.
    private var allArtists: [SearchArtist] { indexer.artists }

    private var artistMatches: [SearchArtist] {
        allArtists.filter { matches($0.name) }
    }

    /// Songs whose *performer* the field found — the one thing the artists scope can hand the songs
    /// scope.
    private var performerMatches: [any Playable] {
        artistMatches.flatMap(\.tracks)
    }

    private var isEmpty: Bool {
        switch scope {
        case .songs, .artists: return songMatches.isEmpty
        case .playlists: return library.playlists.filter { matches($0.name) }.isEmpty
        }
    }

    private func matches(_ text: String) -> Bool {
        SearchTextFold.normalized(text).contains(SearchTextFold.normalized(trimmed))
    }

    /// Tapping a tile or an artist row puts that name in the field, as MeloX's tile does with a genre.
    private func search(_ text: String) {
        scope = .songs
        query = text
    }
}

/// MeloX's media row: 54 pt of artwork at r7, then the name and one line of secondary text
/// (`SearchView.swift:386-408`).
private struct SearchMediaRow<Artwork: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        HStack(spacing: MusicSearchMetrics.mediaGap) {
            artwork()
                .frame(width: MusicSearchMetrics.mediaArt, height: MusicSearchMetrics.mediaArt)
                .clipShape(.rect(cornerRadius: MusicSearchMetrics.mediaArtRadius))

            VStack(alignment: .leading, spacing: MusicSearchMetrics.mediaTextGap) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
