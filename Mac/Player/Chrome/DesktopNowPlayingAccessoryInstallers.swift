import AppKit
import SwiftUI

/// The player's chrome, installed into the window's real titlebar.
///
/// SwiftUI's `.toolbar` puts a `.navigation` item *after* the sidebar's tracking separator, so a button
/// that belongs beside the traffic lights cannot be put there from SwiftUI. A left
/// `NSTitlebarAccessoryViewController` is the AppKit slot that is immediately next to the window
/// controls, and the toolbar itself stays SwiftUI's (`DesktopNowPlayingLeadingAccessoryInstaller.swift:4-11`).
///
/// Both installers are mounted in the root's background, where a zero-size probe can see the window
/// without being in the layout.
struct DesktopNowPlayingLeadingAccessoryInstaller: NSViewRepresentable {
    let isPresented: Bool
    let close: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DesktopNowPlayingAccessoryProbe {
        let probe = DesktopNowPlayingAccessoryProbe()
        probe.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.update(isPresented: isPresented, close: close)
        return probe
    }

    func updateNSView(_ nsView: DesktopNowPlayingAccessoryProbe, context: Context) {
        context.coordinator.update(isPresented: isPresented, close: close)
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: DesktopNowPlayingAccessoryProbe,
                                coordinator: Coordinator) {
        nsView.windowDidChange = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private weak var installedWindow: NSWindow?
        private var isPresented = false
        private var accessoryController: NSTitlebarAccessoryViewController?
        private let hostingView: NSHostingView<DesktopNowPlayingWindowControls>

        init() {
            hostingView = NSHostingView(rootView: DesktopNowPlayingWindowControls(
                close: {}, openMiniPlayer: nil))
            hostingView.frame = NSRect(x: 0, y: 0, width: 36, height: 36)
        }

        func update(isPresented: Bool, close: @escaping () -> Void) {
            self.isPresented = isPresented
            hostingView.rootView = DesktopNowPlayingWindowControls(
                close: close, openMiniPlayer: nil)
            reconcileInstallation()
        }

        func attach(to window: NSWindow?) {
            guard installedWindow !== window else {
                reconcileInstallation()
                return
            }
            detach()
            installedWindow = window
            reconcileInstallation()
        }

        func detach() {
            accessoryController?.removeFromParent()
            accessoryController = nil
            installedWindow = nil
        }

        private func reconcileInstallation() {
            guard let window = installedWindow else { return }
            let isInstalled = accessoryController.map { controller in
                window.titlebarAccessoryViewControllers.contains { $0 === controller }
            } ?? false

            if isPresented, !isInstalled {
                let controller = NSTitlebarAccessoryViewController()
                controller.layoutAttribute = .left
                controller.view = hostingView
                window.addTitlebarAccessoryViewController(controller)
                accessoryController = controller
            } else if !isPresented {
                accessoryController?.removeFromParent()
                accessoryController = nil
            }
        }
    }
}

/// The volume capsule, in the titlebar's right slot.
///
/// The reference rebuilds the hosting view on every presentation rather than reusing one: an accessory
/// controller that has been `removeFromParent()`ed comes back laid out with a stale full-height frame,
/// and a fresh one always lands where the first one did (`DesktopNowPlayingTrailingAccessoryInstaller.swift:95-99`).
struct DesktopNowPlayingTrailingAccessoryInstaller: NSViewRepresentable {
    let isPresented: Bool
    let player: Player

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DesktopNowPlayingAccessoryProbe {
        let probe = DesktopNowPlayingAccessoryProbe()
        probe.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.update(isPresented: isPresented, player: player)
        return probe
    }

    func updateNSView(_ nsView: DesktopNowPlayingAccessoryProbe, context: Context) {
        context.coordinator.update(isPresented: isPresented, player: player)
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: DesktopNowPlayingAccessoryProbe,
                                coordinator: Coordinator) {
        nsView.windowDidChange = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private weak var installedWindow: NSWindow?
        private var isPresented = false
        private var accessoryController: NSTitlebarAccessoryViewController?
        private var hostingView: NSHostingView<AnyView>?

        func update(isPresented: Bool, player: Player) {
            self.isPresented = isPresented
            if let hostingView {
                hostingView.rootView = content(player: player).eraseToAnyView()
            }
            reconcileInstallation(player: player)
        }

        func attach(to window: NSWindow?) {
            guard installedWindow !== window else {
                reconcileInstallation(player: nil)
                return
            }
            detach()
            installedWindow = window
        }

        func detach() {
            accessoryController?.removeFromParent()
            accessoryController = nil
            hostingView = nil
            installedWindow = nil
        }

        private func reconcileInstallation(player: Player?) {
            guard let window = installedWindow else { return }
            let isInstalled = accessoryController.map { controller in
                window.titlebarAccessoryViewControllers.contains { $0 === controller }
            } ?? false

            if isPresented, !isInstalled, let player {
                accessoryController?.removeFromParent()
                let view = NSHostingView(rootView: content(player: player).eraseToAnyView())
                view.layoutSubtreeIfNeeded()
                let fitting = view.fittingSize
                view.frame = NSRect(x: 0, y: 0,
                                    width: max(fitting.width, 150), height: 36)
                let controller = NSTitlebarAccessoryViewController()
                controller.layoutAttribute = .right
                controller.view = view
                window.addTitlebarAccessoryViewController(controller)
                hostingView = view
                accessoryController = controller
            } else if !isPresented {
                accessoryController?.removeFromParent()
                accessoryController = nil
                hostingView = nil
            }
        }

        private func content(player: Player) -> some View {
            DesktopNowPlayingVolumeControl()
                .environmentObject(player)
                .environment(\.colorScheme, .dark)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
    }
}

final class DesktopNowPlayingAccessoryProbe: NSView {
    var windowDidChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
    }
}

private extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}
