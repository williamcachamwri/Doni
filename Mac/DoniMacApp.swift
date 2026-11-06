import AppKit
import SwiftUI

/// The desktop's scene list.
///
/// Everything that *does* something lives one level down: this struct decides how a window opens and
/// what the menu bar offers, and hands the app's live objects to whoever draws them. That split is the
/// reference's (`MeloXDesktopApp.swift`), and it is what makes the delegate the owner of the model —
/// a Dock menu exists before any window does, so it cannot be handed an object a view created.
@main
struct DoniMacApp: App {
    @NSApplicationDelegateAdaptor(DesktopAppDelegate.self) private var appDelegate

    private var model: DesktopAppModel { appDelegate.model }

    init() {
        // The reference disables this for the same reason it has several windows: a player window and a
        // main window are different promises, and folding them into one tab bar is not what a listener
        // asked for.
        NSWindow.allowsAutomaticWindowTabbing = false
        // Following the system language has to happen before any view asks for a word, because the
        // catalog resolves through the language list the process picks up at launch.
        if !DoniLanguage.isChosen {
            DoniLanguage.followDevice()
        }
    }

    var body: some Scene {
        WindowGroup("Doni") {
            DesktopRootView()
                .environment(model)
                // The four the shell draws from. Each pane takes only the ones it reads, so a published
                // change invalidates the rows that show it rather than the whole window.
                .environmentObject(model.session)
                .environmentObject(model.library)
                .environmentObject(model.player)
                .environmentObject(model.indexer)
                .frame(
                    minWidth: DesktopMainWindowMetrics.minimumContentWidth,
                    minHeight: DesktopMainWindowMetrics.minimumContentHeight
                )
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowToolbarLabelStyle(fixed: .iconOnly)
        // The reference's own opening size; the floor is its `DesktopMainWindowMetrics`.
        .defaultSize(width: 1_272, height: 600)
        .commands {
            DesktopCommands(model: model)
        }
    }
}
