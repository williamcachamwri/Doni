import SwiftUI
import TelegramDesignSystem

/// The bar the photo shows: a glass capsule floating 20 pt clear of the phone's left, right and
/// bottom edges, with the list scrolling under it, and a separate 64 pt glass circle for search.
///
/// Nothing here is full-bleed, which is the difference between this and the band `TabBarNode`
/// measures: the reference on the phone draws iOS 26's floating bar, so the bar is glass, the
/// items sit on a measured pitch, and the icon and label take the two centres the photo gives
/// them (`Docs/design-tokens.md`, "The floating tab bar, as photographed").
///
/// Selection is the tab's own Liquid Glass, untouched by a tint: the chosen item gets the same
/// glass the rest of the bar wears, and reads as selected only through its glyph and label, the
/// way iOS 26's own tab bars do. An accent tint behind it drew a blue blob the glyph sank into.
struct TelegramTabBar<Tab: Hashable & CaseIterable & Identifiable>: View where Tab.AllCases == [Tab] {
    @Binding var selection: Tab
    let title: (Tab) -> String
    let symbol: (Tab, Bool) -> String
    /// Doni's own: the one transient count the bar carries, over the tab whose work is still
    /// running. The photo's bar has a badge in exactly this place.
    var badge: (Tab) -> String? = { _ in nil }
    var onSearch: () -> Void = {}

    private let palette = TelegramPalette.dark

    var body: some View {
        HStack(spacing: TelegramFloatingBarMetrics.searchCircleGap) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { tab in
                    item(tab)
                }
            }
            .frame(width: TelegramFloatingBarMetrics.capsuleWidth,
                   height: TelegramFloatingBarMetrics.height)
            .telegramGlass(.capsule, fallback: palette.glassFallback)

            searchCircle
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Điều hướng")
    }

    private func item(_ tab: Tab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            ZStack(alignment: .top) {
                Color.clear
                    .frame(height: TelegramFloatingBarMetrics.height)
                glyph(tab, isSelected: isSelected)
                    .frame(width: TelegramFloatingBarMetrics.itemWidth,
                           height: TelegramFloatingBarMetrics.iconBox)
                    .padding(.top, TelegramFloatingBarMetrics.iconTop)
                    .overlay(alignment: .topTrailing) {
                        badgeView(tab)
                    }
                Text(title(tab))
                    .font(TelegramShellTypography.tabLabel)
                    .foregroundStyle(isSelected ? palette.tabBarSelectedIcon : palette.navSecondaryText)
                    .lineLimit(1)
                    .frame(width: TelegramFloatingBarMetrics.itemWidth,
                           height: TelegramFloatingBarMetrics.labelBox)
                    .padding(.top, TelegramFloatingBarMetrics.labelTop)
            }
            .frame(width: TelegramFloatingBarMetrics.itemWidth)
            // The selected tab's glass goes *behind* the item, exactly as the bar's own glass
            // does: as an overlay it frosted the glyph and the label into an unreadable blue
            // blob, which is what the device showed. Untinted, it reads as the item being on
            // its own pane of glass.
            .background {
                if isSelected {
                    Capsule()
                        .fill(palette.highlight.opacity(0.001))
                        .telegramGlass(.capsule, fallback: palette.glassFallback)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(tab))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func glyph(_ tab: Tab, isSelected: Bool) -> some View {
        Image(systemName: symbol(tab, isSelected))
            .font(.system(size: TelegramFloatingBarMetrics.iconBox,
                          weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? palette.tabBarSelectedIcon : palette.navSecondaryText)
    }

    /// The unread pill's own clothing, in the corner of the icon: `semibold(9)` digits in the
    /// badge's colours, on a pill that never goes under 16 pt.
    @ViewBuilder
    private func badgeView(_ tab: Tab) -> some View {
        if let text = badge(tab) {
            Text(text)
                .font(.system(size: TelegramLibraryMetrics.stateGlyph, weight: .semibold))
                .foregroundStyle(palette.unreadBadgeText)
                .padding(.horizontal, 4)
                .frame(minWidth: TelegramLibraryMetrics.stateSide,
                       minHeight: TelegramLibraryMetrics.stateSide)
                .background(Capsule().fill(palette.unreadBadgeFill))
                .offset(x: 12, y: -6)
                .accessibilityLabel(text)
        }
    }

    private var searchCircle: some View {
        Button(action: onSearch) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: TelegramFloatingBarMetrics.searchGlyph, weight: .regular))
                .foregroundStyle(palette.navPrimaryText)
                .frame(width: TelegramFloatingBarMetrics.searchCircle,
                       height: TelegramFloatingBarMetrics.searchCircle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .telegramGlass(.circle, fallback: palette.glassFallback)
        .accessibilityLabel("Tìm kiếm")
    }
}
