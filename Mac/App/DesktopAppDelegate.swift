import AppKit

/// The Dock menu, which is the reference's (`DesktopAppDelegate.swift:7-66`) and the one piece of its
/// shell that a listener uses without thinking about it: right-click the icon, choose what the song
/// should do next.
///
/// The delegate is also what owns `DesktopAppModel`. That is not a style choice — a menu that exists
/// before any window does cannot be handed an object a view created, so the objects have to outlive the
/// scene the same way the delegate does.
@MainActor
final class DesktopAppDelegate: NSObject, NSApplicationDelegate {
    let model = DesktopAppModel()

    /// ⌘Q goes straight from `terminate:` to `exit()`, and `exit()` runs the C++ destructors that the
    /// TDLib receive thread is still reading through — which is a `SIGSEGV` on the way out, not a clean
    /// quit. The client has to be closed *and joined* before the process starts leaving.
    func applicationWillTerminate(_ notification: Notification) {
        model.session.shutdown()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let playing = model.player.current != nil
        let favourited = model.player.current.map { model.library.isFavorite($0.uniqueId) } == true

        let menu = NSMenu()
        // Without this, AppKit enables an item only when something in the responder chain answers its
        // selector — and while no window is key, that is nothing, so a stopped-out player would grey
        // the whole menu out rather than the two rows that need a song.
        menu.autoenablesItems = false

        menu.addItem(item(
            localized(model.player.isPlaying ? "Tạm dừng" : "Phát"),
            action: #selector(togglePlayback),
            enabled: playing
        ))
        menu.addItem(item(
            localized("Bài trước"),
            action: #selector(playPrevious),
            enabled: model.player.hasPrevious
        ))
        menu.addItem(item(
            localized("Bài tiếp theo"),
            action: #selector(playNext),
            enabled: model.player.hasNext
        ))
        menu.addItem(item(
            localized(favourited ? "Bỏ yêu thích" : "Yêu thích"),
            action: #selector(toggleFavourite),
            enabled: playing
        ))

        menu.addItem(.separator())

        let repeatItem = item(
            localized("Lặp lại"),
            action: #selector(cycleRepeatMode),
            enabled: playing
        )
        repeatItem.state = model.player.repeatMode == .off ? .off : .on
        menu.addItem(repeatItem)

        let shuffleItem = item(
            localized("Phát ngẫu nhiên"),
            action: #selector(toggleShuffle),
            enabled: playing
        )
        shuffleItem.state = model.player.isShuffled ? .on : .off
        menu.addItem(shuffleItem)

        return menu
    }

    private func item(_ title: String, action: Selector, enabled: Bool) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.isEnabled = enabled
        return menuItem
    }

    @objc private func togglePlayback() {
        model.player.toggle()
    }

    @objc private func playPrevious() {
        model.player.previous()
    }

    @objc private func playNext() {
        model.player.next()
    }

    @objc private func toggleFavourite() {
        guard let track = model.player.current else { return }
        model.library.toggleFavorite(track)
    }

    @objc private func cycleRepeatMode() {
        model.player.cycleRepeatMode()
    }

    @objc private func toggleShuffle() {
        model.player.setShuffled(!model.player.isShuffled)
    }
}
