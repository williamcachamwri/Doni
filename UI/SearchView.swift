import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The search tab, after MeloX: the title and the field are the system's, not a header drawn by
/// hand — `.navigationTitle` plus `.searchable(placement: .navigationBarDrawer(displayMode: .always))`
/// (`SearchView.swift:35-40`). Under iOS 26 that field sits in the tab bar's own search role, so it
/// is glass, it grabs the keyboard when the tab is tapped, and it shrinks the bar away as the
/// results scroll.
///
/// What it searches is the whole library, and the fold it searches with is `SearchTextFold`'s, so
/// "tinh yeu" finds "Tình yêu" the way the list always did.
struct SearchView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.displayScale) private var displayScale

    @State private var query = ""

    private let palette = TelegramPalette.dark

    var body: some View {
        List {
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
                    player.play(track, in: visible)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .trackActions(track, library: library)
                .task(id: track.uniqueId) {
                    await artwork.load(track: track, via: session.covers())
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.chatListBackground.ignoresSafeArea())
        .navigationTitle("Tìm kiếm")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm bài hát")
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if !query.isEmpty && visible.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var visible: [any Playable] {
        indexer.matches(of: query)
    }

    private var kept: Set<String> {
        Set(library.favorites.map { $0.track.uniqueId })
    }
}
