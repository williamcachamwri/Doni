import SwiftUI

@main
struct DoniApp: App {
    @StateObject private var session = TelegramSession()
    /// App scope, so a re-render of the list cannot restart the walk through the channel.
    @StateObject private var indexer = LibraryIndexer()

    var body: some Scene {
        WindowGroup {
            if session.isAuthorized {
                LibraryView(session: session, indexer: indexer)
            } else {
                LoginView(session: session)
            }
        }
    }
}
