import SwiftUI
import TelegramDesignSystem

/// The search field as its own floating glass pill, the height of the bar it replaces.
///
/// The list screen has no pill under the bar any more — the tab bar's circle opens this screen —
/// so the field takes the bar's own vessel: a 52 pt capsule holding the loupe, the text and the
/// clear button. The loupe is 20 pt and the text the list's own `regular(17)`; everything else is
/// the field `SearchBarNode` measures, kept where it still applies (the clear button scales
/// instead of fading).
struct SearchField: View {
    @Binding var query: String
    let placeholder: String
    /// The search screen wants the keyboard before anything is typed.
    var autoFocus = false

    @FocusState private var focused: Bool

    private let palette = TelegramPalette.dark

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(palette.searchPlaceholder)
                .frame(width: 34)
            TextField("", text: $query, prompt: Text(placeholder)
                .foregroundStyle(palette.searchPlaceholder))
                .font(TelegramLibraryTypography.searchField)
                .foregroundStyle(palette.navPrimaryText)
                .focused($focused)
                .submitLabel(.done)
            clearButton
        }
        .frame(height: TelegramBarMetrics.height)
        .telegramGlass(.capsule, fallback: palette.glassFallback)
        .onAppear {
            if autoFocus { focused = true }
        }
    }

    /// The clear button does not fade, it scales: 0.2 hidden, 1.0 shown (`SearchBarNode.swift:1647`).
    private var clearButton: some View {
        Button {
            query = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.searchClearButton)
                .frame(width: 40, height: TelegramBarMetrics.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(query.isEmpty ? TelegramLibraryMetrics.clearHiddenScale : 1.0)
        .opacity(query.isEmpty ? 0 : 1)
        .animation(TelegramLoginMotion.easeInOut(0.2), value: query.isEmpty)
        .allowsHitTesting(!query.isEmpty)
        .accessibilityLabel("Xoá")
    }
}
