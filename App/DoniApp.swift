import SwiftUI
import TelegramDesignSystem

@main
struct DoniApp: App {
    @StateObject private var session = TelegramSession()
    /// App scope, so a re-render of the list cannot restart the walk through the channel.
    @StateObject private var indexer = LibraryIndexer()
    /// The same SQLite file the walk writes and the tabs read.
    @StateObject private var library = Library.shared
    @StateObject private var player = Player()
    /// The same cache the lock screen reads, so a row and its artwork never disagree.
    @StateObject private var artwork = CoverArtwork.shared

    var body: some Scene {
        WindowGroup {
            // One ZStack, not one root per state: the shell is put up underneath and the sequence
            // lifts off it on the reference's own spring, which is what makes signing in feel like
            // opening the app rather than switching to another one.
            ZStack {
                // TDLib's first word decides which screen this phone belongs on, and it takes a few
                // hundred milliseconds to say it. Guessing meanwhile put the login gate over a
                // session that was already on the device, which is the flash every launch opened
                // with; this is the same black both screens are already drawn on.
                TelegramListPalette.night.background
                    .ignoresSafeArea()

                if session.hasAnswered {
                    if session.isAuthorized {
                        RootView(session: session, indexer: indexer, player: player,
                                 artwork: artwork, library: library)
                    } else {
                        LoginView(session: session)
                            .transition(.asymmetric(
                                insertion: .identity,
                                removal: .scale(scale: TelegramLoginMotion.leaveScale)
                                    .combined(with: .opacity)
                            ))
                    }
                }
            }
            .animation(TelegramLoginMotion.presentation, value: session.isAuthorized)
            // The client is started here and nowhere else. It used to be the login screen's job, and
            // this screen now waits for TDLib's first word before it draws either of them — a screen
            // that waits for the answer cannot be the one that asks the question. Left as it was,
            // every launch was a black canvas forever.
            .task { session.start() }
        }
    }
}
