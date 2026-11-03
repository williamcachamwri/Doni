import SwiftUI

@main
struct DoniApp: App {
    @StateObject private var session = TelegramSession()

    var body: some Scene {
        WindowGroup {
            if session.isAuthorized {
                DoniRootView()
            } else {
                LoginView(session: session)
            }
        }
    }
}
