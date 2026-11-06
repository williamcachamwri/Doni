import AppKit
import SwiftUI
import TelegramDesignSystem
import UniformTypeIdentifiers

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
    @EnvironmentObject private var player: Player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWindowFullScreen = false
    /// The layer is mounted for the whole of its entrance and its exit, and only *rendering active*
    /// while it is actually on screen — the two flags exist so a page leaving the window can stop
    /// doing display-linked work before it has finished moving (`DesktopRootView.swift:7-9`).
    @State private var isNowPlayingLayerMounted = false
    @State private var isNowPlayingRenderingActive = false

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

        return ZStack {
            DesktopSidebar()

            GeometryReader { proxy in
                if ui.isNowPlayingPresented || isNowPlayingLayerMounted {
                    nowPlayingLayer(
                        isPresented: ui.isNowPlayingPresented,
                        isRenderingActive: isNowPlayingRenderingActive
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(y: ui.isNowPlayingPresented ? 0 : proxy.size.height)
                    .allowsHitTesting(ui.isNowPlayingPresented)
                    .accessibilityHidden(!ui.isNowPlayingPresented)
                    .transition(.move(edge: .bottom))
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .zIndex(1)
            .animation(reduceMotion ? nil : DesktopPlayerMotion.nowPlayingPresentation,
                       value: ui.isNowPlayingPresented)
        }
        .toolbar(removing: .sidebarToggle)
        // The full-screen player takes the titlebar for itself and draws its own controls into it, so
        // the window's toolbar has to be gone by the time it arrives — the reference hides it exactly
        // the same way, and for the same reason (`DesktopRootView.swift:57-61`).
        .toolbarVisibility(
            ui.isNowPlayingPresented && isWindowFullScreen ? .hidden : .automatic,
            for: .windowToolbar
        )
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background {
            ZStack {
                DesktopMainWindowConfiguration(
                    isPlayerSidePanelPresented: ui.inspector != nil,
                    isPlayerPresented: ui.isNowPlayingPresented,
                    isFullScreen: $isWindowFullScreen
                )

                // The player's own chrome lives in the titlebar the way the reference puts it there:
                // a left accessory beside the traffic lights and a right one for the volume. In real
                // full screen the titlebar is gone, so the same two are drawn in content instead
                // (`DesktopRootView.swift:70-83`, `:156-167`).
                DesktopNowPlayingLeadingAccessoryInstaller(
                    isPresented: ui.isNowPlayingPresented && !isWindowFullScreen,
                    close: { model.ui.isNowPlayingPresented = false }
                )

                DesktopNowPlayingTrailingAccessoryInstaller(
                    isPresented: ui.isNowPlayingPresented && !isWindowFullScreen,
                    player: player
                )
            }
            .allowsHitTesting(false)
        }
        .onExitCommand {
            if ui.isNowPlayingPresented { ui.isNowPlayingPresented = false }
        }
        .task(id: ui.isNowPlayingPresented) {
            await updateNowPlayingLifecycle(isPresented: ui.isNowPlayingPresented)
        }
    }

    /// The player and the field behind it (`DesktopRootView.swift:138-172`): the artwork blown up under
    /// a veil, then the window on top, both reading the dark appearance from this root.
    private func nowPlayingLayer(isPresented: Bool, isRenderingActive: Bool) -> some View {
        @Bindable var ui = model.ui

        return ZStack(alignment: .top) {
            DesktopNowPlayingBackdrop(track: player.current, isActive: isRenderingActive)
                .ignoresSafeArea()

            DesktopNowPlayingWindow(isActive: isPresented, isRenderingActive: isRenderingActive)

            // Real full screen has no titlebar to put the accessories in, so the same two controls are
            // drawn here instead — the reference's split, and the reason both halves exist.
            if isWindowFullScreen {
                HStack {
                    DesktopNowPlayingWindowControls(
                        close: { ui.isNowPlayingPresented = false },
                        openMiniPlayer: nil
                    )

                    Spacer()

                    DesktopNowPlayingVolumeControl()
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// Display-linked and geometry-driven work stops *before* the page starts moving, and the mounted
    /// layer stays around only long enough to draw the exit frame (`DesktopRootView.swift:183-234`).
    private func updateNowPlayingLifecycle(isPresented: Bool) async {
        if isPresented {
            commitNowPlayingLayerMounted(true)
            guard await waitForNowPlayingTransition() else { return }
            guard model.ui.isNowPlayingPresented else { return }
            commitNowPlayingRenderingActivity(true)
            return
        }

        commitNowPlayingRenderingActivity(false)
        guard isNowPlayingLayerMounted else { return }
        guard await waitForNowPlayingTransition() else { return }
        guard !model.ui.isNowPlayingPresented else { return }
        commitNowPlayingLayerMounted(false)
    }

    private func waitForNowPlayingTransition() async -> Bool {
        if reduceMotion {
            await Task.yield()
        } else {
            do {
                try await Task.sleep(for: DesktopPlayerMotion.nowPlayingContentDelay)
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }

    private func commitNowPlayingLayerMounted(_ isMounted: Bool) {
        guard isNowPlayingLayerMounted != isMounted else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isNowPlayingLayerMounted = isMounted
        }
    }

    private func commitNowPlayingRenderingActivity(_ isActive: Bool) {
        guard isNowPlayingRenderingActive != isActive else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isNowPlayingRenderingActive = isActive
        }
    }
}

/// One section's page: its own navigation stack, so a channel opened from Home and stepped back out of
/// leaves Home exactly where it was (`DesktopRootView.swift:246-253`).
struct DesktopTabPage: View {
    @Environment(DesktopAppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let section: DesktopSection

    var body: some View {
        @Bindable var ui = model.ui
        let isInspectorPresented = ui.inspector != nil

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
        .navigationTitle(Text(localized(section.title)))

        ZStack(alignment: .trailing) {
            pageContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    DesktopTabBottomPlayerInset()
                }

            // The panel slides in over the column rather than pushing it, because the window has
            // already grown by its 258 points — `DesktopMainWindowConfiguration` does that first, which
            // is what Apple Music does and why the rows never reflow (`DesktopRootView.swift:266-287`).
            DesktopPlayerSidePanel(selection: ui.retainedInspector,
                                   isPresented: isInspectorPresented)
                .frame(width: DesktopMainWindowMetrics.playerSidePanelWidth)
                .offset(x: isInspectorPresented
                    ? 0
                    : DesktopMainWindowMetrics.playerSidePanelWidth)
                .opacity(isInspectorPresented ? 1 : 0)
                .allowsHitTesting(isInspectorPresented)
                .accessibilityHidden(!isInspectorPresented)
                .zIndex(2)
                .animation(reduceMotion ? nil : DesktopMainWindowMetrics.presentationAnimation,
                           value: isInspectorPresented)

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

/// The pane each section draws. The switch is the reference's (`DesktopRootView.swift:329-355`); the
/// bodies are Doni's, because the rows come out of SQLite through `Library` rather than out of an HTTP
/// response.
struct DesktopSectionContentView: View {
    @Environment(DesktopAppModel.self) private var model
    let section: DesktopSection

    var body: some View {
        switch section {
        case .search:
            DesktopSearchPane()
        case .home:
            DesktopHomePane()
        case .recent:
            DesktopTrackPane(title: localized("Gần đây"), tracks: DesktopPanes.recent(model))
        case .liked:
            DesktopTrackPane(title: localized("Yêu thích"), tracks: DesktopPanes.favorites(model))
        case .playlists:
            DesktopPlaylistsPane()
        case .channels:
            DesktopChannelsPane()
        case .cloud:
            DesktopCloudPane()
        case .downloaded:
            DesktopTrackPane(title: localized("Đã tải"), tracks: DesktopPanes.downloaded(model))
        }
    }
}

/// Saved Messages as a library: the same rows, with the two verbs that belong to a file the listener
/// put there themselves — bring one in, take one out.
struct DesktopCloudPane: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var cloud: CloudMusic
    @EnvironmentObject private var session: TelegramSession
    @State private var picking = false

    var body: some View {
        DesktopTrackPane(title: "Cloud Music", tracks: cloud.songs, onUpload: { picking = true })
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { result in
                guard case let .success(urls) = result, !urls.isEmpty else { return }
                let service = cloud, held = session
                Task { await service.upload(held, urls: urls) }
            }
            .task { await cloud.refresh(session) }
    }
}

/// A page pushed onto a section's stack.
struct DesktopRouteView: View {
    let route: DesktopRoute

    var body: some View {
        switch route {
        case let .playlist(id):
            DesktopPlaylistDetail(id: id)
        case let .channel(chatId, title):
            DesktopChannelDetail(chatId: chatId, title: title)
        }
    }
}
