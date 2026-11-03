import SwiftUI

@main
struct DoniApp: App {
    @StateObject private var session = TelegramSession()
    /// App scope, so a re-render of the list cannot restart the walk through the channel.
    @StateObject private var indexer = LibraryIndexer()
    @StateObject private var player = Player()
    /// The same cache the lock screen reads, so a row and its artwork never disagree.
    @StateObject private var artwork = CoverArtwork.shared

    var body: some Scene {
        WindowGroup {
            if session.isAuthorized {
                LibraryView(session: session, indexer: indexer, player: player, artwork: artwork)
            } else {
                LoginView(session: session)
            }
        }
    }
}
