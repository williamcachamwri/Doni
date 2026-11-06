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

    init() {
        // Following the phone is the default and must be written before any view asks for a word: the
        // catalog resolves through the system language list the process picks up at launch, so a matched
        // phone opens in that language from the second launch onward and a Settings choice overrides it.
        guard !DoniLanguage.isChosen else { return }
        DoniLanguage.followDevice()
    }

    var body: some Scene {
        WindowGroup {
            // One ZStack, not one root per state: the shell stays underneath and the sequence lifts off
            // it on the reference's own spring, so signing in feels like opening the app.
            ZStack {
                // TDLib's first word decides which screen this phone belongs on and takes a few hundred
                // ms. Guessing meanwhile flashed the login gate over a session already on the device, so
                // this is the same black both screens are already drawn on.
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
            // The client is started here and nowhere else. It used to be the login screen's job, and a
            // screen that waits for TDLib's answer cannot be the one that asks it: left there, every
            // launch was a black canvas forever.
            .task { session.start() }
            // A session ending somewhere else is the one event no screen can see: TDLib only says it
            // to the client. The four reactions the sign-out button runs by hand are handed over here
            // so that the other path — a desktop logout, a revoked session — runs them too, and
            // awaited, because nothing may write rows while the files are being thrown away.
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
    }
}
