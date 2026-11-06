import AppKit
import SwiftUI
import TelegramDesignSystem

/// The desktop's root, in the shape the reference has it (`DesktopRootView.swift:11-95`).
///
/// Three answers, not one screen per state: TDLib has not spoken yet, so the window opens on the same
/// black the login screen is drawn on; it has spoken and there is no session, so the listener signs in;
/// it has spoken and there is one, so the shell is the sidebar.
///
/// The window behaviour is the copied part — `DesktopMainWindowConfiguration` is the reference's file,
/// byte for byte, including the 258 points it grows the window by before a panel mounts. The *content*
/// is not: the reference's panes bind to NetEase view-models, and Doni's rows come out of SQLite through
/// `Library`, so every pane is written against what this app actually has.
struct DesktopRootView: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var session: TelegramSession
    @State private var isWindowFullScreen = false

    var body: some View {
        @Bindable var ui = model.ui

        content
            .containerBackground(for: .window) {
                Color(nsColor: .windowBackgroundColor)
            }
            // The phone's accent, not the system's: a blue selection in a red app is how a port
            // advertises that its chrome was not chosen.
            .tint(MusicTint.accent)
            .desktopLaunchExperience()
            .sheet(item: $ui.sheet) { sheet in
                switch sheet {
                case .account:
                    DesktopAccountSheet()
                        .environment(model)
                }
            }
            // The client is started here and nowhere else: a screen that waits for TDLib's answer cannot
            // be the one that asks it, and the desktop has no login button to hang it on.
            .task {
                session.start()
                await model.bootstrap()
            }
            .onChange(of: session.isAuthorized) { _, authorized in
                if authorized { model.sessionDidBecomeAuthorized() }
            }
            .onAppear { model.installTeardown() }
    }

    @ViewBuilder private var content: some View {
        if !session.hasAnswered {
            TelegramListPalette.night.background
                .ignoresSafeArea()
        } else if session.isAuthorized {
            shell
        } else {
            DesktopLoginView(session: session)
        }
    }

    private var shell: some View {
        @Bindable var ui = model.ui

        return DesktopSidebar()
            .toolbar(removing: .sidebarToggle)
            // The full-screen player takes the titlebar for itself and draws its own controls into it,
            // so the window's toolbar has to be gone by the time it arrives — the reference hides it
            // exactly the same way, and for the same reason (`DesktopRootView.swift:57-61`).
            .toolbarVisibility(
                ui.isNowPlayingPresented && isWindowFullScreen ? .hidden : .automatic,
                for: .windowToolbar
            )
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .background {
                DesktopMainWindowConfiguration(
                    isPlayerSidePanelPresented: ui.inspector != nil,
                    isPlayerPresented: ui.isNowPlayingPresented,
                    isFullScreen: $isWindowFullScreen
                )
            }
    }
}

/// One section's page: its own navigation stack, so a channel opened from Home and stepped back out of
/// leaves Home exactly where it was (`DesktopRootView.swift:246-253`).
struct DesktopTabPage: View {
    @Environment(DesktopAppModel.self) private var model
    let section: DesktopSection

    var body: some View {
        @Bindable var ui = model.ui

        let pageContent = NavigationStack(path: $ui.path) {
            DesktopSectionContentView(section: section)
                .navigationDestination(for: DesktopRoute.self) { route in
                    DesktopRouteView(route: route)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(removing: .sidebarToggle)
        // A title is what tells a listener which of the eight columns they are looking at once the
        // sidebar has been scrolled out of the way.
        .navigationTitle(localized(section.title))

        ZStack(alignment: .trailing) {
            pageContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    DesktopTabBottomPlayerInset()
                }

            // One bar for the whole app, drawn by the tab the listener is in — the reference's rule, and
            // the reason a hidden tab does not keep a second player tree alive.
            if section == ui.selection {
                DesktopTabBottomPlayer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .zIndex(3)
            }
        }
    }
}

/// The pane each section draws.
///
/// Every one of these says something true — the library's own row counts — because the desktop panes are
/// the next unit of this port. What is *not* placeholder is the machinery around them: the stack, the
/// path, the destination and the sidebar that selects them are the reference's.
struct DesktopSectionContentView: View {
    @EnvironmentObject private var library: Library
    let section: DesktopSection

    var body: some View {
        ContentUnavailableView(
            localized(section.title),
            systemImage: section.systemImage,
            description: Text(countLine)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The library's own numbers, so a shell is honest about being a shell: these are real rows, only
    /// the panes that list them are missing.
    private var countLine: String {
        switch section {
        case .home, .search: return localized("%@ bài", library.trackCount.formatted())
        case .recent: return localized("%@ bài", library.recentlyPlayed.count.formatted())
        case .liked: return localized("%@ bài", library.favorites.count.formatted())
        case .playlists: return localized("%@ danh sách", library.playlists.count.formatted())
        case .channels: return localized("%@ kênh", library.channels.count.formatted())
        case .cloud: return "Saved Messages"
        case .downloaded: return localized("%@ bài trên máy", library.downloadedCount.formatted())
        }
    }
}

/// A detail page pushed onto a section's stack. The name is real — the number of rows inside it is what
/// this port has not written yet.
struct DesktopRouteView: View {
    @EnvironmentObject private var library: Library
    let route: DesktopRoute

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: "music.note.list",
            description: Text(localized("Chưa có danh sách bài ở trang này."))
        )
        .navigationTitle(title)
    }

    private var title: String {
        switch route {
        case let .playlist(id):
            library.playlists.first { $0.id == id }?.name ?? localized("Danh sách")
        case let .channel(_, name):
            name
        }
    }
}
