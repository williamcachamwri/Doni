import SwiftUI
import Support
import TelegramDesignSystem

/// The shell: four tabs, the strip of player above the band, one instance of each screen kept
/// alive once visited.
///
/// A tab is not a `TabView` page. The reference swaps instantly — `TabBarNode` reloads the list
/// it points at and nothing fades — and a `TabView` cannot be made to draw this band, only to hide
/// its own. So the four screens are stacked, the one that is selected is opaque and takes the
/// touches, and the rest keep their scroll position, their queue and their artwork the way
/// Telegram's own controllers do when you come back to a tab.
///
/// The chrome floats: the bar and the strip are glass capsules 20 pt clear of the phone's edges and
/// the lists run under them to the physical bottom of the screen, which is what the photo shows and
/// what `Docs/design-tokens.md`, "The floating tab bar, as photographed" measures. Search is not a
/// field in a list but the circle beside the bar, so it opens its own screen.
struct RootView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var selection = DoniTab.library

    /// Tabs opened at least once. A tab that has never been picked is not built, so the four lists
    /// do not each ask the network for artwork the user has not looked at.
    @State private var visited: Set<DoniTab> = [.library]

    @State private var showsSearch = false
    @State private var showsPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(DoniTab.allCases) { tab in
                if visited.contains(tab) {
                    screen(tab)
                        .opacity(selection == tab ? 1 : 0)
                        .allowsHitTesting(selection == tab)
                }
            }

            chrome
        }
        // The lists reach the physical bottom so their rows can pass under the glass; the top safe
        // area still belongs to the bar.
        .ignoresSafeArea(edges: .bottom)
        .environment(\.telegramFloatingClearance,
                     TelegramFloatingBarMetrics.clearance(stripVisible: player.current != nil))
        .fullScreenCover(isPresented: $showsPlayer) {
            NowPlayingView(player: player, artwork: artwork, library: library)
        }
        .overlay {
            if showsSearch {
                SearchView(session: session, indexer: indexer, player: player,
                           artwork: artwork, library: library) {
                    showsSearch = false
                }
                .transition(.opacity)
            }
        }
        .animation(TelegramLoginMotion.easeInOut(0.2), value: showsSearch)
        .preferredColorScheme(.dark)
    }

    /// The strip over the bar, both floating, both 20 pt clear of the edges — the two capsules read
    /// as one stack because they keep the same margin and one gap between them.
    @ViewBuilder
    private var chrome: some View {
        VStack(spacing: TelegramFloatingBarMetrics.stripGap) {
            if player.current != nil {
                MiniPlayerBar(player: player, artwork: artwork) { showsPlayer = true }
                    .transition(.offset(y: TelegramShellMetrics.miniPlayerHeight)
                        .combined(with: .opacity))
            }
            TelegramTabBar(selection: binding) { $0.title }
                symbol: { tab, isSelected in tab.symbol(selected: isSelected) }
                badge: { tab in
                    // The count the bar used to carry in its subtitle, in the slot the photo puts a
                    // badge: only while the channel is actually being read.
                    guard tab == .library, indexer.isReading else { return nil }
                    return indexer.tracks.count.formatted()
                }
                onSearch: { showsSearch = true }
        }
        .padding(.horizontal, TelegramFloatingBarMetrics.margin)
        .padding(.bottom, TelegramFloatingBarMetrics.margin)
        .animation(TelegramShellMotion.appear, value: player.current?.uniqueId)
    }

    @ViewBuilder
    private func screen(_ tab: DoniTab) -> some View {
        switch tab {
        case .library:
            LibraryView(session: session, indexer: indexer, player: player,
                        artwork: artwork, library: library)
        case .likes:
            LikesView(session: session, player: player, artwork: artwork, library: library)
        case .playlists:
            PlaylistsView(session: session, player: player, artwork: artwork, library: library)
        case .settings:
            SettingsView(session: session, library: library)
        }
    }

    private var binding: Binding<DoniTab> {
        Binding(
            get: { selection },
            set: { tab in
                visited.insert(tab)
                selection = tab
            }
        )
    }
}

/// The four tabs, named the way the screens name themselves on screen.
enum DoniTab: String, CaseIterable, Identifiable {
    case library
    case likes
    case playlists
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Thư viện"
        case .likes: return "Yêu thích"
        case .playlists: return "Danh sách"
        case .settings: return "Cài đặt"
        }
    }

    /// Filled when lit, outline when not — the reference's own way of saying which tab is current
    /// without changing a colour (`DefaultDarkPresentationTheme.swift:362-365`). Two of the four
    /// have no outline form, and those are told apart by the lit glass and by the glyph's weight.
    func symbol(selected: Bool) -> String {
        switch self {
        case .library: return "music.note.list"
        case .likes: return selected ? "heart.fill" : "heart"
        case .playlists: return "music.quarternote.3"
        case .settings: return selected ? "gearshape.fill" : "gearshape"
        }
    }
}

#Preview {
    RootView(session: TelegramSession(), indexer: LibraryIndexer(), player: Player(),
             artwork: CoverArtwork.shared, library: Library.shared)
}
