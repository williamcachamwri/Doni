import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The screen the tab bar's search circle opens, after the Apple Music set: the title set left in
/// `bold(34)`, a full-width rounded field under it, and Huỷ stepping in only while the field holds
/// the keyboard.
///
/// What it searches is the whole library, and the fold it searches with is `SearchTextFold`'s, so
/// "tinh yeu" finds "Tình yêu" the way the list always did.
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
    @State private var editing = false

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
            HStack(spacing: TelegramHeaderMetrics.actionGap) {
                SearchField(query: $query, placeholder: "Tìm bài hát",
                            autoFocus: true, isEditing: $editing)
                if editing {
                    Button("Huỷ", action: close)
                        .font(TelegramShellTypography.barAction)
                        .foregroundStyle(palette.highlight)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .padding(.horizontal, TelegramHeaderMetrics.sideInset)
        .padding(.top, TelegramHeaderMetrics.topPadding)
        .padding(.bottom, TelegramHeaderMetrics.bottomPadding)
        .animation(TelegramLoginMotion.easeInOut(0.2), value: editing)
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
        .contentMargins(.top, TelegramHeaderMetrics.searchClearance, for: .scrollContent)
        .contentMargins(.bottom, floatingClearance, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }
}
