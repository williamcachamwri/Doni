import SwiftUI
import Support
import TelegramDesignSystem

/// The shell, the way the reference builds it: a system `TabView`, the mini player in the tab bar's own
/// glass accessory, and the player as a cover the artwork zooms into (`ContentView.swift:332-394`).
/// All of it is system chrome on iOS 26 — the glass bar, the accessory slot, scroll-minimising, and
/// `matchedTransitionSource` for the zoom. Two namespaces keep it straight: one for the strip's trip
/// into the player, one shared by every tab's cards for their trip into a playlist.
struct RootView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var selection = DoniTab.home

    /// The strip disappears while the panel is up, the way the reference suppresses its accessory
    /// (`ContentView.swift:40`, `:337`).
    @State private var showsPlayer = false

    /// One namespace for the cover's trip between the strip and the panel
    /// (`ContentView.swift:44-47`).
    @Namespace private var playerSpace

    /// A second one for a card's trip into the screen it opens. The reference keeps these apart
    /// (`ContentView.swift:44-45`): a player's artwork and a playlist's cover are different covers, and
    /// one id must not mean two things in the same namespace.
    @Namespace private var musicSpace

    private let transitionID = "player-art"

    var body: some View {
        playerAwareTabs
            .fullScreenCover(isPresented: $showsPlayer) {
                NowPlayingView(session: session, player: player, artwork: artwork,
                               library: library, close: { showsPlayer = false })
                    // `presentationBackground(.clear)`: the panel paints its own backdrop from the
                    // cover's average colour, so the system sheet chrome must be transparent for it
                    // to show (`:103`). The glass accessory resizes with the drag rather than sitting
                    // rigid under it (`:104`).
                    .presentationBackground(.clear)
                    .presentationContentInteraction(.resizes)
                    .navigationTransition(.zoom(sourceID: transitionID, in: playerSpace))
            }
            .tint(MusicTint.accent)
            .preferredColorScheme(.dark)
            .appLaunchChecks()
    }

    /// The 26.0 form of `tabViewBottomAccessory` has no `isEnabled:`, so the content itself comes and
    /// goes — the same split MeloX makes (`ContentView.swift:334-348`).
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
            Tab(LocalizedStringKey(DoniTab.home.title), systemImage: DoniTab.home.symbol,
                value: DoniTab.home) {
                NavigationStack {
                    LibraryView(session: session, indexer: indexer, player: player,
                                artwork: artwork, library: library,
                                onOpenTab: { selection = $0 },
                                onOpenPlayer: { showsPlayer = true })
                }
            }
            Tab(LocalizedStringKey(DoniTab.likes.title), systemImage: DoniTab.likes.symbol, value: DoniTab.likes) {
                NavigationStack {
                    LikesView(session: session, player: player, artwork: artwork,
                              library: library)
                }
            }
            Tab(LocalizedStringKey(DoniTab.playlists.title), systemImage: DoniTab.playlists.symbol,
                value: DoniTab.playlists) {
                NavigationStack {
                    PlaylistsView(session: session, player: player, artwork: artwork,
                                  library: library)
                }
            }
            // The slot the reference gives its cloud drive (`Features/Cloud/CloudMusicView.swift`),
            // holding the files the user brought: it needs the library, the player and the covers,
            // not the session or the walk. The account sits in the header's avatar instead
            // (`ContentView.swift:453-457`).
            // The channels as their own door: the reference keeps the places the music comes from
            // beside the lists the listener made, and a grid of pictures is how both are drawn.
            Tab(LocalizedStringKey(DoniTab.channels.title), systemImage: DoniTab.channels.symbol,
                value: DoniTab.channels) {
                NavigationStack {
                    ChannelsView(session: session, indexer: indexer, player: player,
                                 artwork: artwork, library: library)
                }
            }
            Tab(LocalizedStringKey(DoniTab.cloud.title), systemImage: DoniTab.cloud.symbol, value: DoniTab.cloud) {
                NavigationStack {
                    CloudMusicView(session: session, player: player, artwork: artwork, library: library)
                }
            }
            // The reference's search tab: a `Tab` with the `.search` role whose content is a
            // `.searchable` list, not a field drawn by hand (`ContentView.swift:371`).
            Tab(LocalizedStringKey(DoniTab.search.title), systemImage: DoniTab.search.symbol,
                value: DoniTab.search, role: .search) {
                    NavigationStack {
                        SearchView(session: session, indexer: indexer, player: player,
                                   artwork: artwork, library: library)
                    }
                }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Every tab's stack is handed the same namespace, which is what lets a shelf card on one tab
        // zoom into a screen pushed on it (`ContentView.swift:385-393`).
        .environment(\.musicNavigationNamespace, musicSpace)
    }
}

/// The six tabs, named and dressed as the reference names them (`NavigationPreferences.swift:22-60`,
/// `:16,:36,:56` for the cloud title and `icloud` glyph). One outline glyph each: the glass selection
/// says which tab is current, so a filled variant would only fight it.
enum DoniTab: String, CaseIterable, Identifiable {
    case home
    case likes
    case playlists
    case channels
    case cloud
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Trang chủ"
        case .likes: return "Yêu thích"
        case .playlists: return "Danh sách"
        case .channels: return "Kênh"
        case .cloud: return "Cloud Music"
        case .search: return "Tìm kiếm"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .likes: return "heart"
        case .playlists: return "music.quarternote.3"
        case .channels: return "antenna.radiowaves.left.and.right"
        case .cloud: return "icloud"
        case .search: return "magnifyingglass"
        }
    }
}

#Preview {
    RootView(session: TelegramSession(), indexer: LibraryIndexer(), player: Player(),
             artwork: CoverArtwork.shared, library: Library.shared)
}
