import SwiftUI
import Support
import TelegramDesignSystem

/// The shell: five tabs under the strip-and-bar, one instance of each screen kept alive once
/// visited.
///
/// A tab is not a `TabView` page. MeloX does use one (`ContentView.swift:365`), but only because
/// iOS 26 lets a `TabView` host the mini player through `.tabViewBottomAccessory` and minimise the
/// bar on scroll; Doni's floor is iOS 17, where neither exists, and a `TabView` cannot be made to
/// draw this chrome, only to hide its own. So the screens are stacked, the one that is selected is
/// opaque and takes the touches, and the rest keep their scroll position, their queue and their
/// artwork — which is also what a `TabView` gives each tab, by keeping its own state alive.
///
/// The player is not a cover but a layer of the same hierarchy, because that is the only way to run
/// the morph: the strip's artwork becomes the cover's, and a drag down slides the panel after the
/// finger while the shell rises back. The chrome sits on one backdrop that runs from the strip's top
/// to the physical bottom, blurred and darkening downward.
struct RootView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var selection = DoniTab.library

    /// Tabs opened at least once. A tab that has never been picked is not built, so the five lists
    /// do not each ask the network for artwork the user has not looked at.
    @State private var visited: Set<DoniTab> = [.library]

    @State private var showsPlayer = false
    /// How far down the player is being dragged, 0…1 — read back from the panel so the shell can
    /// rise while the finger pulls.
    @State private var dragProgress: CGFloat = 0

    @Namespace private var playerSpace

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { edge in
                shell(homeInset: edge.safeAreaInsets.bottom)
            }
            // The lists reach the physical bottom so their rows can pass under the chrome's blur;
            // the reader reads the home indicator's own inset out of the expanded frame.
            .ignoresSafeArea(edges: .bottom)

            if showsPlayer {
                NowPlayingView(player: player, artwork: artwork, library: library,
                               namespace: playerSpace, dragProgress: $dragProgress,
                               close: { showsPlayer = false })
                    .zIndex(3)
                    .transition(.opacity)
            }
        }
        // The kit runs its morph on `UIViewPropertyAnimator(duration: 0.5, dampingRatio: 1)`
        // (`AMNowPlayingAnimationController.swift:75`) — a critical spring, no overshoot.
        .animation(.spring(response: 0.5, dampingFraction: 1.0), value: showsPlayer)
        .preferredColorScheme(.dark)
    }

    private func shell(homeInset: CGFloat) -> some View {
        let lift = min(max(dragProgress, 0), 1)
        return ZStack(alignment: .bottom) {
            ForEach(DoniTab.allCases) { tab in
                if visited.contains(tab) {
                    screen(tab)
                        .opacity(selection == tab ? 1 : 0)
                        .allowsHitTesting(selection == tab)
                }
            }

            chrome
                .padding(.bottom, homeInset)
                .background { ChromeBackdrop() }
        }
        .environment(\.telegramFloatingClearance,
                     homeInset + TelegramFloatingBarMetrics
                         .clearance(stripVisible: player.current != nil))
        .scaleEffect(0.85 + 0.15 * lift)
        .clipShape(RoundedRectangle(cornerRadius: 30 + 14 * lift, style: .continuous))
    }

    /// The strip over the bar, on Doni's own gap of 6, the strip inset 12 from each edge
    /// (`MiniPlayerView.swift:92`).
    @ViewBuilder
    private var chrome: some View {
        VStack(spacing: TelegramFloatingBarMetrics.toolbarToTabBar) {
            if player.current != nil {
                MiniPlayerBar(player: player, artwork: artwork,
                              namespace: playerSpace, isSource: !showsPlayer) {
                    showsPlayer = true
                }
                .padding(.horizontal, TelegramFloatingBarMetrics.toolbarMargin)
                .opacity(showsPlayer ? 0 : 1)
                .transition(.offset(y: MusicMiniPlayerMetrics.height)
                    .combined(with: .opacity))
            }
            AMTabBar(selection: binding)
        }
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
        case .search:
            SearchView(session: session, indexer: indexer, player: player,
                       artwork: artwork, library: library)
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

/// The kit's backdrop: one blur under the whole chrome, darkening downward, its top edge fading
/// in over a sliver so rows melt under it (`AMTabBarBackdropView.swift`: blur 30 behind a mask
/// that is near-opaque, and a gradient overlay that runs black 0 → 0.8 by 40% down —
/// `Tab-Bar-Backdrop-Overlay`, dark appearance).
private struct ChromeBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black, location: 0.05),
                ], startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(0.8), location: 0.4),
                ], startPoint: .top, endPoint: .bottom)
            }
    }
}

/// The five tabs, named and dressed the way MeloX names them
/// (`NavigationPreferences.swift:22-60`; home first, search last, and neither end movable —
/// `AppSettings.swift:1901-1914`, `TabLayoutSettingsView.swift:88`).
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

    /// Filled when lit, outline when not — the reference's own way of saying which tab is current
    /// without changing a colour (`DefaultDarkPresentationTheme.swift:362-365`). Three of the five
    /// have no outline form, and those are told apart by the lit glass and by the glyph's weight.
    func symbol(selected: Bool) -> String {
        switch self {
        case .library: return "music.note.list"
        case .likes: return selected ? "heart.fill" : "heart"
        case .playlists: return "music.quarternote.3"
        case .settings: return selected ? "gearshape.fill" : "gearshape"
        case .search: return "magnifyingglass"
        }
    }
}

#Preview {
    RootView(session: TelegramSession(), indexer: LibraryIndexer(), player: Player(),
             artwork: CoverArtwork.shared, library: Library.shared)
}
