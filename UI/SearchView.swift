import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The search tab, after MeloX: the title set left in `bold(34)` and a full-width field under it,
/// which is what `SearchView.swift:35-40` asks the system for with `.navigationTitle` plus a
/// `.searchable(placement: .navigationBarDrawer(displayMode: .always))` — a bar that is always
/// open, so it needs no Huỷ to close it and no keyboard grabbed before anyone wants one.
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
    @Environment(\.telegramFloatingClearance) private var floatingClearance

    @State private var query = ""

    private let palette = TelegramPalette.dark

    var body: some View {
        ZStack(alignment: .top) {
            rows
            header
                .background(palette.chatListBackground)
        }
        .background(palette.chatListBackground.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TelegramHeaderMetrics.actionGap) {
            Text("Tìm kiếm")
                .font(TelegramShellTypography.largeTitle)
                .foregroundStyle(palette.navPrimaryText)
            SearchField(query: $query, placeholder: "Tìm bài hát")
        }
        .padding(.horizontal, TelegramHeaderMetrics.sideInset)
        .padding(.top, TelegramHeaderMetrics.topPadding)
        .padding(.bottom, TelegramHeaderMetrics.bottomPadding)
    }

    private var visible: [any Playable] {
        indexer.matches(of: query)
    }

    private var rows: some View {
        let kept = Set(library.favorites.map { $0.track.uniqueId })
        return ScrollView {
            LazyVStack(spacing: 0) {
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
                    .trackActions(track, library: library)
                    .task(id: track.uniqueId) {
                        await artwork.load(track: track, via: session.covers())
                    }
                }
                if !query.isEmpty && visible.isEmpty {
                    Text("Không tìm thấy “\(query)”")
                        .font(TelegramLibraryTypography.preview)
                        .foregroundStyle(palette.chatListMessageText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
        }
        .contentMargins(.top, TelegramHeaderMetrics.searchClearance, for: .scrollContent)
        .contentMargins(.bottom, floatingClearance, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }
}
