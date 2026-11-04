import SwiftUI
import TelegramDesignSystem

/// MeloX's tab bar: every tab is a real one — home first, search last
/// (`AppSettings.swift:1901-1914` builds the default order as `[.home] + content pages + [.search]`,
/// and `TabLayoutSettingsView.swift:88` refuses to move either end) — each a glyph over a 10 pt
/// label, exactly as `Tab(tab.title, systemImage: tab.systemImage, …)` (`ContentView.swift:367-372`)
/// hands them to the system bar.
///
/// The bar itself is the system's on iOS 26, so on Doni's iOS 17 floor it is hand-built. The one
/// colour decision transcribed is the selection: MeloX sets `.tint(.red)` on the whole scene
/// (`MeloXApp.swift:95`) and the system bar paints the current tab with the tint, so lit here
/// means `MusicTint.accent` and nothing else changes.
struct AMTabBar: View {
    @Binding var selection: DoniTab

    private let palette = TelegramPalette.dark

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DoniTab.allCases) { tab in
                item(tab)
            }
        }
        .frame(height: TelegramShellMetrics.tabBarHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Điều hướng")
    }

    private func item(_ tab: DoniTab) -> some View {
        let isSelected = selection == tab
        let color = isSelected ? MusicTint.accent : palette.navSecondaryText
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol(selected: isSelected))
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(color)
                    .frame(height: 24)
                Text(tab.title)
                    .font(TelegramShellTypography.tabLabel)
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
