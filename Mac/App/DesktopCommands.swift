import SwiftUI

/// The menu bar, in the shape the reference has it (`DesktopCommands.swift`): a Controls menu, a
/// Navigate menu, and a System half whose job is to *remove* things.
///
/// The removing matters as much as the adding. A music player that offers ⌘N for a second window, a
/// sidebar toggle that would leave the window showing nothing, or a Help menu with no help book behind
/// it has told the listener that nobody chose these.
///
/// One rule runs through the whole file, and it is the reason no row here prints `player.isPlaying`:
/// `Commands` are built by the scene, and the scene is not invalidated by a published change inside an
/// `ObservableObject` the way a view is. A title or a `disabled` read taken at build time can therefore
/// go stale mid-song — the Controls menu would keep saying "Phát" over a playing track. What the app is
/// *doing* is read inside the action, at the press, where it is always current; what a row is *called*
/// never depends on it.
struct DesktopCommands: Commands {
    let model: DesktopAppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            // The standard about panel says one fact — the version — while the settings panel's
            // About card says every one of them, so the menu row leads there instead.
            Button("Giới thiệu về Doni") {
                model.ui.openSettingsAtAbout = true
                model.ui.sheet = .settings
            }
        }
        DesktopSystemCommands()
        DesktopPlaybackCommands(model: model)
        DesktopNavigationCommands(model: model)
    }
}

private struct DesktopSystemCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .systemServices) {}
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .sidebar) {}
        CommandGroup(replacing: .windowArrangement) {}
        CommandGroup(replacing: .help) {}
    }
}

private struct DesktopPlaybackCommands: Commands {
    let model: DesktopAppModel

    var body: some Commands {
        CommandMenu("Điều khiển") {
            Button("Phát / Tạm dừng") {
                model.player.toggle()
            }
            .keyboardShortcut(DesktopPlaybackKeyboardShortcuts.togglePlayback)

            Button("Bài trước") {
                model.player.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Bài tiếp theo") {
                model.player.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button("Phát ngẫu nhiên") {
                let player = model.player
                player.setShuffled(!player.isShuffled)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Lặp lại") {
                model.player.cycleRepeatMode()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Divider()

            // The two panel doors. Their buttons are on the bar, but the bar folds them away when the
            // volume opens, and a listener who has learned the key does not care what is on screen.
            Button("Lời bài hát") { model.ui.toggleInspector(.lyrics) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Hàng đợi") { model.ui.toggleInspector(.queue) }
                .keyboardShortcut("q", modifiers: [.command, .shift])
        }
    }
}

private struct DesktopNavigationCommands: Commands {
    let model: DesktopAppModel

    var body: some Commands {
        CommandMenu("Điều hướng") {
            Button("Tìm kiếm") { model.ui.selection = .search }
                .keyboardShortcut("f", modifiers: .command)
            Button("Trang chủ") { model.ui.selection = .home }
                .keyboardShortcut("1", modifiers: .command)

            Divider()

            Button("Yêu thích") { model.ui.selection = .liked }
                .keyboardShortcut("2", modifiers: .command)
            Button("Danh sách") { model.ui.selection = .playlists }
                .keyboardShortcut("3", modifiers: .command)
            Button("Kênh") { model.ui.selection = .channels }
                .keyboardShortcut("4", modifiers: .command)
            Button("Cloud Music") { model.ui.selection = .cloud }
                .keyboardShortcut("5", modifiers: .command)
        }
    }
}

enum DesktopPlaybackKeyboardShortcuts {
    /// macOS 15 does not register a modifier-less `KeyEquivalent.space`, so the reference registers the
    /// space *character* instead (`DesktopPlaybackKeyboardShortcuts.swift:4-9`) — which every supported
    /// macOS accepts, and which resolves to one action when the player bar registers the same key.
    static let togglePlayback = KeyboardShortcut(" ", modifiers: [])
}
