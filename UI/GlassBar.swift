import SwiftUI
import TelegramDesignSystem

/// One icon in the bar's trailing group.
struct GlassBarAction {
    let symbol: String
    let label: String
    let run: () -> Void
}

/// The bar on top of a screen: a floating glass pill, rounded like the tab bar it faces.
///
/// The first build drew the photo's full-bleed band and the user rejected it on the device — so
/// the band became a pill carrying the same contents: a centred large title, a text action at the
/// leading edge, icon actions at the trailing one. The actions sit directly on the glass rather
/// than in nested capsules, because the pill itself is now the vessel the photo's band was.
/// `Docs/design-tokens.md`, "The bar, as photographed"; the pill's own numbers are in
/// `TelegramBarMetrics` and marked Doni's own there.
struct GlassBar: View {
    let title: String
    /// The word in the leading action — the photo's is "Sửa".
    var leading: String?
    var onLeading: (() -> Void)?
    /// A chevron instead of the leading word, for a bar that sits over a list you can leave.
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
                leadingItem
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
    /// the guard from what the bar actually holds, with a width-per-character estimate for the
    /// leading word.
    private var edgeSpan: CGFloat {
        let leadingSpan: CGFloat
        if onBack != nil {
            leadingSpan = TelegramBarMetrics.actionPitch
        } else if let leading {
            leadingSpan = CGFloat(leading.count) * 10 + 2 * TelegramBarMetrics.textPadding
        } else {
            leadingSpan = 0
        }
        let trailingSpan = CGFloat(actions.count) * TelegramBarMetrics.actionPitch
        return max(leadingSpan, trailingSpan)
    }

    @ViewBuilder
    private var leadingItem: some View {
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
        } else if let leading, let onLeading {
            Button(action: onLeading) {
                Text(leading)
                    .font(TelegramShellTypography.barAction)
                    .foregroundStyle(palette.navPrimaryText)
                    .padding(.horizontal, TelegramBarMetrics.textPadding)
                    .frame(height: TelegramBarMetrics.contentHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(leading)
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
