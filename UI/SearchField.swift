import SwiftUI
import TelegramDesignSystem

/// Telegram's `.modern` search pill, which the library and the hearts both sit under.
///
/// 36 tall with a 21/2 corner, the loupe 5 pt inside the fill and the text 24, the clear button
/// scaled to 0.2 rather than faded, and a "Huỷ" that only exists while the field has focus —
/// all of it `SearchBarNode.swift`, quoted in `Docs/design-tokens.md`.
struct SearchField: View {
    @Binding var query: String
    let placeholder: String

    @FocusState private var focused: Bool

    private let palette = TelegramPalette.dark

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: TelegramLibraryMetrics.searchCornerRadius)
                    .fill(palette.searchInputFill)
                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: TelegramLibraryMetrics.loupeSide, weight: .regular))
                        .foregroundStyle(palette.searchPlaceholder)
                        .frame(width: TelegramLibraryMetrics.loupeSide)
                    if query.isEmpty {
                        Text(placeholder)
                            .font(TelegramLibraryTypography.searchField)
                            .foregroundStyle(palette.searchPlaceholder)
                    }
                }
                .padding(.leading, TelegramLibraryMetrics.loupeInset)
                .allowsHitTesting(false)
                TextField("", text: $query)
                    .font(TelegramLibraryTypography.searchField)
                    .foregroundStyle(palette.navPrimaryText)
                    .focused($focused)
                    .padding(.leading, TelegramLibraryMetrics.fieldTextInset)
                    .padding(.trailing, query.isEmpty
                        ? TelegramLibraryMetrics.searchPadding
                        : TelegramLibraryMetrics.clearWidth)
                    .submitLabel(.done)
                clearButton
            }
            .frame(height: TelegramLibraryMetrics.searchFieldHeight)

            if focused {
                Button("Huỷ") {
                    query = ""
                    focused = false
                }
                .font(TelegramLibraryTypography.searchField)   // Cancel without a custom title is `regular(17)`
                .foregroundStyle(palette.accent)
                .padding(.leading, 11)
                .transition(.opacity)
            }
        }
        .animation(TelegramLoginMotion.easeInOut(0.2), value: focused)
        .padding(.horizontal, TelegramLibraryMetrics.searchPadding)
        .padding(.top, TelegramLibraryMetrics.searchPadding)
        .padding(.bottom, TelegramLibraryMetrics.searchBelow)
    }

    /// The clear button does not fade, it scales: 0.2 hidden, 1.0 shown (`:1647`).
    private var clearButton: some View {
        Button {
            query = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(palette.searchClearButton)
                .frame(width: TelegramLibraryMetrics.clearWidth,
                       height: TelegramLibraryMetrics.searchFieldHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .scaleEffect(query.isEmpty ? TelegramLibraryMetrics.clearHiddenScale : 1.0)
        .opacity(query.isEmpty ? 0 : 1)
        .animation(TelegramLoginMotion.easeInOut(0.2), value: query.isEmpty)
        .allowsHitTesting(!query.isEmpty)
    }
}
