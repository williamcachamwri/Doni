import SwiftUI

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
            if session.isAuthorized {
                LibraryView(session: session, indexer: indexer, player: player,
                            artwork: artwork, library: library)
            } else {
                LoginView(session: session)
            }
        }
    }
}
