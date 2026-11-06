import AppKit

@MainActor
final class DesktopPlayerToolbarController {
    private weak var window: NSWindow?
    private var transparentToolbarWindows: [ToolbarWindowAppearance] = []
    private var windowUpdateObserver: NSObjectProtocol?
    private var isPlayerPresented = false
    private var isApplyingChange = false
    private var contentExtendsUnderTitlebar = false

    func update(isPlayerPresented: Bool) {
        self.isPlayerPresented = isPlayerPresented
        synchronize()
    }

    func attach(to window: NSWindow?) {
        guard self.window !== window else {
            synchronize()
            return
        }
        detach()
        self.window = window
        guard window != nil else { return }
        windowUpdateObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // The one line changed from the reference's file, and only because this target compiles
            // Swift 6 with complete concurrency while the reference is Swift 5: handing a `Notification`
            // across an isolation region is refused. The block is already queued on the main queue, so
            // nothing here is ever touched off-thread — `nonisolated(unsafe)` states that fact instead
            // of restructuring the check into a different behaviour. Filtering to `object: window`
            // would look cleaner and would break this: in full screen the titlebar is a *child* window,
            // and its updates are exactly what has to re-apply the transparency.
            nonisolated(unsafe) let carried = notification
            MainActor.assumeIsolated {
                guard let self, let window = self.window,
                      let updatedWindow = carried.object as? NSWindow,
                      updatedWindow === window || updatedWindow.parent === window else {
                    return
                }
                self.synchronize()
            }
        }
        synchronize()
    }

    func detach() {
        if let windowUpdateObserver {
            NotificationCenter.default.removeObserver(windowUpdateObserver)
        }
        windowUpdateObserver = nil
        restoreToolbarWindows()
        window = nil
    }

    private func synchronize() {
        guard let window, !isApplyingChange else { return }
        isApplyingChange = true
        defer { isApplyingChange = false }

        let immersive = isPlayerPresented && window.styleMask.contains(.fullScreen)
        extendContentUnderTitlebar(window, immersive: immersive)

        if immersive {
            makeToolbarWindowsTransparent(in: window)
        } else {
            restoreToolbarWindows()
        }
    }

    /// Doni's own, and the reason it is not in the file it was copied from: hiding the toolbar in real
    /// full screen leaves its ~52 points *reserved*, so the player's backdrop began under a black band
    /// across the top of the screen. `.fullSizeContentView` is what makes the content view the whole
    /// screen, and a transparent titlebar stops AppKit drawing a bar over it. Both come back out again
    /// the moment the player is dismissed or the window leaves full screen, because in an ordinary
    /// window the content must not slide under the traffic lights.
    private func extendContentUnderTitlebar(_ window: NSWindow, immersive: Bool) {
        guard immersive != contentExtendsUnderTitlebar else { return }
        contentExtendsUnderTitlebar = immersive
        if immersive {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            return
        }
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .automatic
    }

    private func makeToolbarWindowsTransparent(in window: NSWindow) {
        // The native full-screen titlebar is a full-width, borderless child
        // at the screen's top edge. Its internal background can still draw
        // over a transparent window background. Keep its content transparent
        // while AppKit animates the child window's own opacity on hover.
        let topInset = NSStatusBar.system.thickness
        for child in window.childWindows ?? [] {
            let frame = child.frame
            guard child.styleMask.isEmpty,
                  abs(frame.minX - window.frame.minX) < 1,
                  abs(frame.width - window.frame.width) < 1,
                  frame.height <= topInset * 3,
                  abs(frame.maxY - window.frame.maxY) <= topInset * 2,
                  let contentView = child.contentView else {
                continue
            }
            if !transparentToolbarWindows.contains(where: { $0.window === child }) {
                transparentToolbarWindows.append(ToolbarWindowAppearance(
                    window: child,
                    contentView: contentView,
                    contentAlphaValue: contentView.alphaValue,
                    ignoresMouseEvents: child.ignoresMouseEvents
                ))
            }
            if contentView.alphaValue != 0 {
                contentView.alphaValue = 0
            }
            if !child.ignoresMouseEvents {
                child.ignoresMouseEvents = true
            }
        }
    }

    private func restoreToolbarWindows() {
        for appearance in transparentToolbarWindows {
            appearance.contentView?.alphaValue = appearance.contentAlphaValue
            appearance.window?.ignoresMouseEvents = appearance.ignoresMouseEvents
        }
        transparentToolbarWindows.removeAll()
    }

    private struct ToolbarWindowAppearance {
        weak var window: NSWindow?
        weak var contentView: NSView?
        let contentAlphaValue: CGFloat
        let ignoresMouseEvents: Bool
    }
}
