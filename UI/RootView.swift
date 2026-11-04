import SwiftUI
import Support
import TelegramDesignSystem

/// The shell, the way the reference builds it: a system `TabView`, the mini player hung in the tab
/// bar's own glass accessory, and the player a cover the artwork zooms into
/// (`ContentView.swift:332-394`).
///
/// Every part of this chrome is the system's now. What Doni used to hand-build — a bar of five
/// buttons, a strip floating on a blurred backdrop, a header drawn from measured numbers — was a
/// substitute for APIs the old deployment target did not have. On iOS 26 they are simply there:
/// the bar is glass and tints the selected tab, the accessory slot is where a mini player lives,
/// the bar gets out of the way when the list scrolls, and a `matchedTransitionSource` hands the
/// cover to the zoom instead of a geometry effect pretending to.
struct RootView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var selection = DoniTab.library

    /// The strip disappears while the panel is up, the way the reference suppresses its accessory
    /// (`ContentView.swift:40`, `:337`).
    @State private var showsPlayer = false

    /// One namespace for the cover's trip between the strip and the panel
    /// (`ContentView.swift:44-47`).
    @Namespace private var playerSpace

    private let transitionID = "player-art"

    var body: some View {
        playerAwareTabs
            .fullScreenCover(isPresented: $showsPlayer) {
                NowPlayingView(session: session, player: player, artwork: artwork,
                               library: library, close: { showsPlayer = false })
                    // The panel paints its own backdrop from the cover's average colour, so the
                    // system's sheet chrome has to be transparent for it to show (`:103`), and the
                    // strip's glass resizes with it rather than sitting rigid under the drag (`:104`).
                    .presentationBackground(.clear)
                    .presentationContentInteraction(.resizes)
                    .navigationTransition(.zoom(sourceID: transitionID, in: playerSpace))
            }
            .tint(MusicTint.accent)
            .preferredColorScheme(.dark)
    }

    /// The 26.0 form of the accessory has no `isEnabled:`, so the content itself is what comes and
    /// goes — MeloX makes exactly the same split (`ContentView.swift:334-348`).
    @ViewBuilder
    private var playerAwareTabs: some View {
        if player.current != nil {
            if #available(iOS 26.1, *) {
                tabs.tabViewBottomAccessory(isEnabled: !showsPlayer) { miniPlayer }
            } else {
                tabs.tabViewBottomAccessory {
                    if !showsPlayer { miniPlayer }
                }
            }
        } else {
            tabs
        }
    }

    private var miniPlayer: some View {
        MiniPlayerBar(player: player, artwork: artwork,
                      transitionID: transitionID, namespace: playerSpace,
                      open: { showsPlayer = true })
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab(DoniTab.library.title, systemImage: DoniTab.library.symbol,
                value: DoniTab.library) {
                NavigationStack {
                    LibraryView(session: session, indexer: indexer, player: player,
                                artwork: artwork, library: library,
                                onOpenTab: { selection = $0 },
                                onOpenPlayer: { showsPlayer = true })
                }
            }
            Tab(DoniTab.likes.title, systemImage: DoniTab.likes.symbol, value: DoniTab.likes) {
                NavigationStack {
                    LikesView(session: session, player: player, artwork: artwork,
                              library: library)
                }
            }
            Tab(DoniTab.playlists.title, systemImage: DoniTab.playlists.symbol,
                value: DoniTab.playlists) {
                NavigationStack {
                    PlaylistsView(session: session, player: player, artwork: artwork,
                                  library: library)
                }
            }
            Tab(DoniTab.settings.title, systemImage: DoniTab.settings.symbol,
                value: DoniTab.settings) {
                NavigationStack {
                    SettingsView(session: session, library: library)
                }
            }
            // The reference's own search tab: a `Tab` with the search role, whose content is a
            // `.searchable` list rather than a field drawn by hand (`ContentView.swift:371`).
            Tab(DoniTab.search.title, systemImage: DoniTab.search.symbol,
                value: DoniTab.search, role: .search) {
                    NavigationStack {
                        SearchView(session: session, indexer: indexer, player: player,
                                   artwork: artwork, library: library)
                    }
                }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// The five tabs, named and dressed the way the reference names them
/// (`NavigationPreferences.swift:22-60`). One outline glyph each: the glass selection is what says
/// which tab is current, so a filled variant would only fight it.
enum DoniTab: String, CaseIterable, Identifiable {
    case library
    case likes
    case playlists
    case settings
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Thư viện"
        case .likes: return "Yêu thích"
        case .playlists: return "Danh sách"
        case .settings: return "Cài đặt"
        case .search: return "Tìm kiếm"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "music.note.list"
        case .likes: return "heart"
        case .playlists: return "music.quarternote.3"
        case .settings: return "gearshape"
        case .search: return "magnifyingglass"
        }
    }
}

#Preview {
    RootView(session: TelegramSession(), indexer: LibraryIndexer(), player: Player(),
             artwork: CoverArtwork.shared, library: Library.shared)
}
