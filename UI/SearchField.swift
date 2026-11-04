import SwiftUI
import TelegramDesignSystem

/// The search field: a rounded grey glass field, not a capsule.
///
/// The loupe is 20 pt and the text the list's own `regular(17)`; everything else is the field
/// `SearchBarNode` measures, kept where it still applies (the clear button scales instead of
/// fading). The field never grabs the keyboard itself — MeloX's `.searchable` bar is always on
/// screen and only focuses when it is tapped (`SearchView.swift:36-40`).
struct SearchField: View {
    @Binding var query: String
    let placeholder: String

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
                .submitLabel(.done)
            clearButton
        }
        .frame(height: TelegramHeaderMetrics.fieldHeight)
        .telegramGlass(.field, fallback: palette.glassFallback)
    }

    /// The clear button does not fade, it scales: 0.2 hidden, 1.0 shown (`SearchBarNode.swift:1647`).
    private var clearButton: some View {
        Button {
            query = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.searchClearButton)
                .frame(width: 40, height: TelegramHeaderMetrics.fieldHeight)
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
