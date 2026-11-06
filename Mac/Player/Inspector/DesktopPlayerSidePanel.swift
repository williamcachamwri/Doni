import SwiftUI
import TelegramDesignSystem

/// The trailing panel, exactly as the reference builds it (`DesktopPlayerSidePanel.swift`): the page
/// that is leaving keeps rendering through the dismissal so the glass and its content travel as one
/// sheet, and the one arriving is mounted at the start of the presentation rather than after it.
///
/// The 258 points it occupies are not taken from the list — `DesktopMainWindowConfiguration` grows the
/// window by that much first, which is what Apple Music does and the reason the rows do not reflow.
struct DesktopPlayerSidePanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renderingSelection: DesktopInspector?

    let selection: DesktopInspector
    let isPresented: Bool

    var body: some View {
        surfacedPanel
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(localized(selection.title)))
            .task(id: RenderingRequest(selection: selection, isPresented: isPresented)) {
                await updateRenderingSelection()
            }
    }

    @ViewBuilder private var surfacedPanel: some View {
        if isPresented || renderingSelection != nil {
            if #available(macOS 26.0, *) {
                crossfadingContent.background {
                    Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 0))
                }
            } else {
                crossfadingContent.background {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
        } else {
            Color.clear
        }
    }

    private var crossfadingContent: some View {
        ZStack {
            if renderingSelection != nil {
                DesktopPlayerInspector(kind: selection,
                                       isActive: isPresented && renderingSelection == selection)
                    .id(selection)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : DesktopMainWindowMetrics.presentationAnimation,
                   value: selection)
        .clipped()
    }

    private func updateRenderingSelection() async {
        guard isPresented else {
            if !reduceMotion {
                do {
                    try await Task.sleep(for: .seconds(
                        DesktopMainWindowMetrics.presentationDuration))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            commitRenderingSelection(nil)
            return
        }
        commitRenderingSelection(selection)
    }

    private func commitRenderingSelection(_ selection: DesktopInspector?) {
        guard renderingSelection != selection else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            renderingSelection = selection
        }
    }
}

private struct RenderingRequest: Hashable {
    let selection: DesktopInspector
    let isPresented: Bool
}

/// The panel's two questions about the same song.
struct DesktopPlayerInspector: View {
    let kind: DesktopInspector
    var isActive = true

    var body: some View {
        Group {
            switch kind {
            case .lyrics: DesktopLyricsPane(isActive: isActive)
            case .queue: DesktopQueuePane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
