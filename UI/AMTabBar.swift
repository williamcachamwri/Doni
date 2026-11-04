import SwiftUI
import TelegramDesignSystem

/// The kit's tab bar: a full-width transparent bar whose items are the system's own — a glyph
/// over a `medium(10)` label, the whole width of the screen, no capsule and no separate search
/// circle (`AMTabBarController.swift`). Search rides in the bar as its fifth item, which is how
/// a fifth tab would sit.
struct AMTabBar: View {
    @Binding var selection: DoniTab
    /// Doni's own: the one transient count the bar carries, over the tab whose work is still
    /// running — the slot a system badge occupies.
    var badge: (DoniTab) -> String? = { _ in nil }
    var onSearch: () -> Void = {}

    private let palette = TelegramPalette.dark

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DoniTab.allCases) { tab in
                item(tab)
            }
            searchItem
        }
        .frame(height: TelegramShellMetrics.tabBarHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Điều hướng")
    }

    private func item(_ tab: DoniTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol(selected: isSelected))
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(isSelected ? palette.tabBarSelectedIcon : palette.navSecondaryText)
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        badgeView(tab)
                    }
                Text(tab.title)
                    .font(TelegramShellTypography.tabLabel)
                    .foregroundStyle(isSelected ? palette.tabBarSelectedIcon : palette.navSecondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var searchItem: some View {
        Button(action: onSearch) {
            VStack(spacing: 2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(palette.navSecondaryText)
                    .frame(height: 24)
                Text("Tìm kiếm")
                    .font(TelegramShellTypography.tabLabel)
                    .foregroundStyle(palette.navSecondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tìm kiếm")
    }

    /// The unread pill's own clothing, in the corner of the icon: `semibold(9)` digits in the
    /// badge's colours, on a pill that never goes under 16 pt.
    @ViewBuilder
    private func badgeView(_ tab: DoniTab) -> some View {
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
}
