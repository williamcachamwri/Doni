import SwiftUI
import TelegramDesignSystem

/// The four tabs, drawn to the band `TabBarNode` measures.
///
/// Selection is not a colour change: in dark the icon, the selected icon and the label are all
/// `#ffffff` (`DefaultDarkPresentationTheme.swift:362-365`), so the reference marks the current tab
/// by the glyph it draws and nothing else. Doni adds the glass capsule the design lab picked —
/// a filled symbol over a 36 × 24 pill, which is the shape Apple's own tab bar lights, and the one
/// thing in this bar that is not a number from the reference.
///
/// The band is 49 pt whatever the phone is, with the safe area painted under it rather than eaten
/// into it (`TabBarController.swift:204-206`), so the list can travel behind the material.
struct TelegramTabBar<Tab: Hashable & CaseIterable & Identifiable>: View where Tab.AllCases == [Tab] {
    @Binding var selection: Tab
    let title: (Tab) -> String
    let symbol: (Tab, Bool) -> String

    @Environment(\.displayScale) private var displayScale

    private let palette = TelegramPalette.dark

    /// Doni's own: the glyph's glass pill is a fifth wider than the reference's 24 pt box, which is
    /// the proportion Apple gives a lit tab item.
    private let capsuleWidth: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                item(tab)
            }
        }
        .frame(height: TelegramShellMetrics.tabBarHeight)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                palette.barBlurredBackground
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.tabBarSeparator)
                .frame(height: TelegramGeometry.hairline(displayScale: displayScale))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Điều hướng")
    }

    private func item(_ tab: Tab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: TelegramShellMetrics.tabIconToLabel) {
                glyph(tab, isSelected: isSelected)
                    .frame(width: capsuleWidth, height: TelegramShellMetrics.tabGlyphSide)
                    .modifier(OptionalGlass(isSelected: isSelected,
                                            tint: palette.tabBarIcon.opacity(0.25),
                                            fallback: palette.tabBarIcon.opacity(0.16)))
                Text(title(tab))
                    .font(TelegramShellTypography.tabLabel)
                    .foregroundStyle(palette.tabBarText)
                    .lineLimit(1)
            }
            .frame(height: TelegramShellMetrics.tabItemHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(tab))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func glyph(_ tab: Tab, isSelected: Bool) -> some View {
        Image(systemName: symbol(tab, isSelected))
            .font(.system(size: TelegramShellMetrics.tabGlyphSide,
                          weight: isSelected ? .semibold : .regular))
            .foregroundStyle(palette.tabBarIcon)
    }
}

/// Glass only under the tab that is lit; an unlit item wears nothing.
private struct OptionalGlass: ViewModifier {
    let isSelected: Bool
    let tint: Color
    let fallback: Color

    func body(content: Content) -> some View {
        if isSelected {
            content.telegramGlass(.tintedCapsule(tint), fallback: fallback)
        } else {
            content
        }
    }
}
