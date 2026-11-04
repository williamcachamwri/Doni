import SwiftUI
import TelegramDesignSystem

/// One icon in the bar's trailing group.
struct GlassBarAction {
    let symbol: String
    let label: String
    let run: () -> Void
}

/// The pill a pushed screen wears: a floating glass capsule holding a chevron back, the screen's
/// centred title and its icon actions.
///
/// It is the detail screens' bar only — the tab screens moved to `LargeTitleHeader`, whose titles
/// are set left and too wide to centre on a pill. The pill's numbers are in `TelegramBarMetrics`
/// and marked Doni's own there.
struct GlassBar: View {
    let title: String
    /// A chevron back, for a bar that sits over a list you can leave.
    var onBack: (() -> Void)?
    var actions: [GlassBarAction] = []

    private let palette = TelegramPalette.dark

    var body: some View {
        ZStack {
            Text(title)
                .font(TelegramShellTypography.barLargeTitle)
                .foregroundStyle(palette.navPrimaryText)
                .lineLimit(1)
                .padding(.horizontal, edgeSpan + TelegramBarMetrics.titleGuard)
            HStack(spacing: 0) {
                backItem
                Spacer(minLength: 0)
                trailingGroup
            }
        }
        .frame(height: TelegramBarMetrics.contentHeight)
        .padding(.horizontal, TelegramBarMetrics.padding)
        .frame(height: TelegramBarMetrics.height)
        .frame(maxWidth: .infinity)
        .telegramGlass(.capsule, fallback: palette.barBlurredBackground)
        .padding(.horizontal, TelegramBarMetrics.sideInset)
        .padding(.top, TelegramBarMetrics.topGap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// How far the centred title must keep from each side. The first build padded by the photo's
    /// *three*-icon group whatever the screen had, and "Thư viện" drew as "Thứ v…"; this derives
    /// the guard from what the bar actually holds.
    private var edgeSpan: CGFloat {
        max(onBack == nil ? 0 : TelegramBarMetrics.actionPitch,
            CGFloat(actions.count) * TelegramBarMetrics.actionPitch)
    }

    @ViewBuilder
    private var backItem: some View {
        if let onBack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: TelegramBarMetrics.actionGlyph, weight: .semibold))
                    .foregroundStyle(palette.navPrimaryText)
                    .frame(width: TelegramBarMetrics.actionPitch,
                           height: TelegramBarMetrics.contentHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quay lại")
        }
    }

    @ViewBuilder
    private var trailingGroup: some View {
        ForEach(actions, id: \.label) { action in
            Button(action: action.run) {
                Image(systemName: action.symbol)
                    .font(.system(size: TelegramBarMetrics.actionGlyph, weight: .regular))
                    .foregroundStyle(palette.navPrimaryText)
                    .frame(width: TelegramBarMetrics.actionPitch,
                           height: TelegramBarMetrics.contentHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.label)
        }
    }
}
