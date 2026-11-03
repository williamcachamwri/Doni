import SwiftUI
import Support
import TelegramDesignSystem

/// The screen the tab bar's search circle opens.
///
/// The photo's list has no field in it — search is the circle, not a pill under the bar — so the
/// field lives here instead, in the one screen Telegram gives it its own bar. What it searches is
/// the whole library, and the fold it searches with is `SearchTextFold`'s, so "tinh yeu" finds
/// "Tình yêu" the way the list always did.
struct SearchView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    let close: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.telegramFloatingClearance) private var floatingClearance

    @State private var query = ""

    private let palette = TelegramPalette.dark

    var body: some View {
        VStack(spacing: 0) {
            GlassBar(title: "Tìm kiếm", leading: "Huỷ", onLeading: close)
            SearchField(query: $query, placeholder: "Tìm bài hát", autoFocus: true)
            rows
        }
        .background(palette.chatListBackground.ignoresSafeArea())
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
                        close()
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
        .contentMargins(.bottom, floatingClearance, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }
}
