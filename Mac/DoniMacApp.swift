import AppKit
import SwiftUI
import TelegramDesignSystem

@main
struct DoniMacApp: App {
    /// The same five app-scoped objects the phone builds, for the same reasons: a re-render of the list
    /// must not restart the walk, and the player, the cache and the library have to be the objects every
    /// pane reads.
    @StateObject private var session = TelegramSession()
    @StateObject private var indexer = LibraryIndexer()
    @StateObject private var library = Library.shared
    @StateObject private var player = Player()
    @StateObject private var artwork = CoverArtwork.shared

    init() {
        // The reference disables this for the same reason it has multiple windows: a player window and
        // a main window are different promises, and folding them into one tab bar is not what a
        // listener asked for.
        NSWindow.allowsAutomaticWindowTabbing = false
        // Following the system language has to happen before any view asks for a word, because the
        // catalog resolves through the language list the process picks up at launch.
        if !DoniLanguage.isChosen {
            DoniLanguage.followDevice()
        }
    }

    var body: some Scene {
        WindowGroup("Doni") {
            DesktopRootView(session: session, library: library, player: player)
                .frame(
                    minWidth: DesktopMainWindowMetrics.minimumContentWidth,
                    minHeight: DesktopMainWindowMetrics.minimumContentHeight
                )
                .task { session.start() }
                // On the phone this hand-off lives in `LibraryView`, the first pane that ever needs
                // bytes — which is why a Mac build that has no Library tab yet would play silence:
                // `Player.stream` begins with `guard let downloader`. The bind belongs to the root,
                // next to the client it depends on, and `covers()` is lazy and idempotent so calling it
                // here costs nothing when a view calls it too.
                .onChange(of: session.isAuthorized) { _, authorized in
                    guard authorized else { return }
                    player.bind(session.covers())
                    indexer.run(session, library: library)
                }
                // A session ending somewhere else is the one event no screen can see. The phone's root
                // registers the same four reactions; the desktop must not be the place that forgets
                // them, because a Mac left playing after a logout is the defect that started this.
                .onAppear {
                    let walk = indexer, sound = player, books = library, pictures = artwork
                    session.onSessionEnded = {
                        walk.reset()
                        sound.stop()
                        _ = await books.wipe()
                        _ = pictures.clearCache()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowToolbarLabelStyle(fixed: .iconOnly)
        // The reference's own opening size; the floor is its `DesktopMainWindowMetrics`.
        .defaultSize(width: 1_272, height: 600)
    }
}
