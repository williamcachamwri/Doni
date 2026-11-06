import SwiftUI
import Support

#if os(iOS)
    import UIKit

    struct SystemShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]
        var onComplete: ((Bool) -> Void)?

        init(
            activityItems: [Any],
            onComplete: ((Bool) -> Void)? = nil
        ) {
            self.activityItems = activityItems
            self.onComplete = onComplete
        }

        func makeUIViewController(
            context: Context
        ) -> UIActivityViewController {
            let viewController = UIActivityViewController(
                activityItems: activityItems,
                applicationActivities: nil
            )
            viewController.completionWithItemsHandler = {
                _, completed, _, _ in
                onComplete?(completed)
            }
            return viewController
        }

        func updateUIViewController(
            _ uiViewController: UIActivityViewController,
            context: Context
        ) {}
    }
#else
    import AppKit

    /// The desktop's share menu is a different shape of thing, not a missing one:
    /// `NSSharingServicePicker` is the system's own service list, it takes plain items instead of a
    /// per-activity source, and it answers nothing about what the user did with them.
    ///
    /// So `onComplete` never fires here, and the caller's "shared" feedback stays the phone's — claiming
    /// success the moment the menu opens would report a share that may never have happened.
    ///
    /// Provisional on purpose: the desktop's own lyrics surface is being rebuilt on the reference app's
    /// Mac chrome, and that chrome has its own share affordance. This exists so the package is not the
    /// reason the core cannot compile.
    struct SystemShareSheet: NSViewRepresentable {
        let activityItems: [Any]
        var onComplete: ((Bool) -> Void)?

        init(
            activityItems: [Any],
            onComplete: ((Bool) -> Void)? = nil
        ) {
            self.activityItems = activityItems
            self.onComplete = onComplete
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            let picker = NSSharingServicePicker(items: activityItems)
            // Not during the build of the view: the anchor has to be in the window before a picker can
            // place itself against it.
            DispatchQueue.main.async {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }
#endif
