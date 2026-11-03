import SwiftUI
import Support
import TelegramDesignSystem

/// The shell: four tabs, the strip of player above the band, one instance of each screen kept
/// alive once visited.
///
/// A tab is not a `TabView` page. The reference swaps instantly — `TabBarNode` reloads the list
/// it points at and nothing fades — and a `TabView` cannot be made to draw this band, only to hide
/// its own. So the four screens are stacked, the one that is selected is opaque and takes the
/// touches, and the rest keep their scroll position, their search text and their queue the way
/// Telegram's own controllers do when you come back to a tab.
///
/// The strip and the full-screen player it opens live here rather than in each screen, so a song
/// keeps playing across a tab change and the player cover is presented once, above everything.
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

    var body: some View {
        ZStack {
            ForEach(DoniTab.allCases) { tab in
                if visited.contains(tab) {
                    screen(tab)
                        .opacity(selection == tab ? 1 : 0)
                        .allowsHitTesting(selection == tab)
                }
            }
        }
        .playerStrip(player: player, artwork: artwork, library: library)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TelegramTabBar(selection: binding) { $0.title }
                symbol: { tab, isSelected in tab.symbol(selected: isSelected) }
        }
        .preferredColorScheme(.dark)
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
    /// have no outline form, and those are told apart by the glass and by the glyph's weight.
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
