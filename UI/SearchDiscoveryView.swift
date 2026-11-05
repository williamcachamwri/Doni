import SwiftUI
import Support
import TelegramDesignSystem

/// The screen MeloX puts behind an empty search field (`SearchDiscoveryView.swift:16-45`): sections 28
/// apart, each a `.title2.bold()` heading with 14 down to its content, over 8 pt of scroll padding,
/// with pull-to-refresh on top.
/// The same furniture carries what this store holds: the user's own lists on the shelf, and the
/// channel's artists as tiles, each tapping straight into a search for that name.
struct SearchDiscoveryView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    /// The artists the index knows, biggest first. The grid shows the first twelve.
    let artists: [SearchArtist]
    /// Tapping a tile searches that artist.
    let search: (String) -> Void

    private static let tileLimit = 12

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MusicSearchMetrics.sectionSpacing) {
                shelf
                categories
            }
            .padding(.vertical, MusicSearchMetrics.verticalPadding)
        }
        .refreshable {
            await indexer.reload(session, library: library)
        }
    }

    @ViewBuilder
    private var shelf: some View {
        let lists = library.playlists
        if !lists.isEmpty {
            VStack(alignment: .leading, spacing: MusicSearchMetrics.headingToContent) {
                Text("Danh sách của bạn")
                    .font(.title2.bold())
                    .padding(.horizontal, MusicSearchMetrics.shelfMargin)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: MusicSearchMetrics.shelfGap) {
                        ForEach(lists) { list in
                            NavigationLink(value: list.id) {
                                card(list)
                            }
                            .buttonStyle(.plain)
                            .musicMatchedTransitionSource(playlistID: list.id)
                        }
                    }
                }
                .contentMargins(.horizontal, MusicSearchMetrics.shelfMargin, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
        }
    }

    /// A 172 pt card: the list's picture, then two lines of words under it
    /// (`SearchDiscoveryView.swift:66-78`, `MediaCardView.swift:11-28`).
    private func card(_ list: StoredPlaylist) -> some View {
        let cover = library.firstTrack(in: list.id)
        return VStack(alignment: .leading, spacing: MusicFeedMetrics.cardTextGap) {
            PlaylistArt(listId: list.id, coverPath: list.coverPath, cover: cover,
                        side: MusicSearchMetrics.shelfCard,
                        radius: MusicArtworkMetrics.radius, artwork: artwork)
                .task(id: list.id) {
                    if let cover {
                        // The card draws 172 but orders the hero's 300, so the cover the zoom flies
                        // out of is the one the detail draws (`MusicNavigationTransitions.swift:48-52,
                        // 65-68`).
                        await artwork.load(track: cover, via: session.covers(),
                                           side: MusicArtworkMetrics.heroSide)
                    }
                }

            Text(list.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(localized("%@ bài", list.trackCount.formatted()))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: MusicSearchMetrics.shelfCard, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var categories: some View {
        if artists.isEmpty {
            ContentUnavailableView(
                "Chưa có gì để gợi ý",
                systemImage: "magnifyingglass",
                description: Text("Thư viện vẫn đang được đọc.")
            )
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: MusicSearchMetrics.headingToContent) {
                Text("Nghệ sĩ")
                    .font(.title2.bold())

                LazyVGrid(columns: columns, spacing: MusicSearchMetrics.gridSpacing) {
                    ForEach(Array(artists.prefix(Self.tileLimit).enumerated()),
                            id: \.element.id) { position, artist in
                        SearchCategoryTile(
                            title: artist.name,
                            systemImage: Self.glyphs[position % Self.glyphs.count],
                            colors: Self.pair(at: position)
                        ) {
                            search(artist.name)
                        }
                        .accessibilityHint(localized("%@ bài", artist.tracks.count.formatted()))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: MusicSearchMetrics.gridSpacing),
              count: MusicSearchMetrics.gridColumns)
    }

    /// The reference's category glyphs (`SearchDiscoveryView.swift:175-196`), cycled: a tile here is an
    /// artist, with no genre of its own to draw.
    private static let glyphs = ["music.mic", "mic.fill", "guitars.fill",
                                 "pianokeys", "waveform", "music.note"]

    /// MeloX's two-colour category pairs, the same six the home tiles use, cycled in order
    /// (`HomeQuickActionsView.swift:81-96`).
    private static func pair(at position: Int) -> [Color] {
        let pairs = MusicQuickActionMetrics.gradientPairs
        let pair = pairs[position % pairs.count]
        return [pair.from, pair.to]
    }
}

/// MeloX's category card: a diagonal gradient, a 60 pt bold watermark turned −8° into the top
/// trailing corner at white 0.22, the name in `.title3.bold()` at the bottom leading, all of it 1.55
/// wide to tall inside 14 pt of radius (`SearchDiscoveryView.swift:117-146`).
private struct SearchCategoryTile: View {
    let title: String
    let systemImage: String
    let colors: [Color]
    let search: () -> Void

    var body: some View {
        Button(action: search) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)

                Image(systemName: systemImage)
                    .font(.system(size: MusicSearchMetrics.tileGlyph, weight: .bold))
                    .foregroundStyle(.white.opacity(MusicSearchMetrics.tileGlyphInk))
                    .rotationEffect(.degrees(MusicSearchMetrics.tileGlyphRotation))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(MusicSearchMetrics.tilePadding)

                // Either a category this app named or an artist it read; a name not in the catalog
                // comes back as itself.
                Text(LocalizedStringKey(title))
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(MusicSearchMetrics.tileLabelMinScale)
                    .padding(MusicSearchMetrics.tilePadding)
            }
            .aspectRatio(MusicSearchMetrics.tileAspect, contentMode: .fit)
            .clipShape(.rect(cornerRadius: MusicSearchMetrics.tileRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// One artist's name and the songs carrying it — the facet a Telegram channel has in place of genres.
struct SearchArtist: Identifiable {
    let name: String
    let tracks: [any Playable]

    var id: String { name }

    /// An artist's artwork is the artwork of a song it is on; the first is the newest.
    var sample: any Playable { tracks[0] }
}

extension Array where Element == any Playable {
    /// Grouped by performer, biggest first, then by name — MeloX's category order before filtering.
    var searchArtists: [SearchArtist] {
        var grouped: [String: [any Playable]] = [:]
        for track in self where !track.displayPerformer.trimmedSearchName.isEmpty {
            grouped[track.displayPerformer.trimmedSearchName, default: []].append(track)
        }
        return grouped.map { SearchArtist(name: $0.key, tracks: $0.value) }
            .sorted { lhs, rhs in
                lhs.tracks.count == rhs.tracks.count ? lhs.name < rhs.name
                                                      : lhs.tracks.count > rhs.tracks.count
            }
    }
}

extension String {
    /// Performer fields are bot-written text padded with spaces; an empty one is truly empty once the
    /// pad is gone.
    var trimmedSearchName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
