import AppKit
import SwiftUI
import TdBridge

@main
struct DoniMacApp: App {
    init() {
        // The reference disables this for the same reason it has one: a player
        // window and a main window are different promises, and the system folding
        // them into one tab bar is never what a listener asked for.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("Doni") {
            MacLaunchProbe()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        // 1272×600 opening, 980×540 floor — the reference's own numbers, from
        // `MeloXDesktopApp` and `DesktopMainWindowMetrics`, kept as literals until
        // the file that names them is ported over.
        .defaultSize(width: 1_272, height: 600)
    }
}

/// The window the MeloX chrome will be poured into. Until that chrome arrives this
/// carries the one fact worth proving about a Mac build: TDLib answers here.
private struct MacLaunchProbe: View {
    @State private var verdict = "TDLib: đang hỏi…"

    var body: some View {
        Text(verdict)
            .font(.system(.title3, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 980, minHeight: 540)
            .task { verdict = TdTransport.probe() }
    }
}
