import SwiftUI
import TelegramDesignSystem

/// One icon in the bar's trailing group.
struct GlassBarAction {
    let symbol: String
    let label: String
    let run: () -> Void
}

/// The bar the photo shows, which is not the bar the source describes.
///
/// `Docs/design-tokens.md`, "The bar, as photographed": a glass band 66.7 pt under the safe area
/// with **no rule under it** and nothing full-bleed inside it — a centred large title, one *text*
/// action in a capsule 16 pt from the left, and a group of icon actions in a single capsule that
/// ends 16 pt from the right, each item on a 38.9 pt pitch. The reference's own bar is
/// `DocumentPreviewController`'s `semibold(17)`; the phone was running a build that draws iOS 26's
/// glass bar, and the photo is the oracle, so the title is the `semibold(22)` its ink height
/// measures and the band is real glass.
struct GlassBar: View {
    let title: String
    /// The word in the leading capsule — the photo's is "Sửa". Doni puts the thing it replaces
    /// here rather than an icon, because the measured action is text: 12 pt of glass on each side
    /// of the ink.
    var leading: String?
    var onLeading: (() -> Void)?
    /// A chevron instead of the leading capsule, for a bar that sits over a list you can leave.
    var onBack: (() -> Void)?
    var actions: [GlassBarAction] = []

    private let palette = TelegramPalette.dark

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: TelegramBarMetrics.capsuleTop)
            ZStack {
                Text(title)
                    .font(TelegramShellTypography.barLargeTitle)
                    .foregroundStyle(palette.navPrimaryText)
                    .lineLimit(1)
                    .padding(.horizontal, TelegramBarMetrics.actionGroupWidth + 24)
                HStack(spacing: 0) {
                    leadingItem
                    Spacer(minLength: 0)
                    trailingGroup
                }
            }
            .frame(height: TelegramBarMetrics.capsuleHeight)
            .padding(.horizontal, TelegramBarMetrics.sideInset)
            Color.clear
                .frame(height: TelegramBarMetrics.height
                    - TelegramBarMetrics.capsuleTop
                    - TelegramBarMetrics.capsuleHeight)
        }
        .frame(height: TelegramBarMetrics.height)
        .frame(maxWidth: .infinity)
        .telegramGlass(.band, fallback: palette.barBlurredBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var leadingItem: some View {
        if let onBack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: TelegramBarMetrics.actionGlyph, weight: .semibold))
                    .foregroundStyle(palette.navPrimaryText)
                    .frame(width: TelegramBarMetrics.actionPitch,
                           height: TelegramBarMetrics.capsuleHeight)
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
                    .frame(height: TelegramBarMetrics.capsuleHeight)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .telegramGlass(.capsule, fallback: palette.glassFallback)
            .accessibilityLabel(leading)
        }
    }

    @ViewBuilder
    private var trailingGroup: some View {
        if !actions.isEmpty {
            HStack(spacing: 0) {
                ForEach(actions, id: \.label) { action in
                    Button(action: action.run) {
                        Image(systemName: action.symbol)
                            .font(.system(size: TelegramBarMetrics.actionGlyph, weight: .regular))
                            .foregroundStyle(palette.navPrimaryText)
                            .frame(width: TelegramBarMetrics.actionPitch,
                                   height: TelegramBarMetrics.capsuleHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.label)
                }
            }
            .frame(width: TelegramBarMetrics.actionPitch * CGFloat(actions.count))
            .telegramGlass(.capsule, fallback: palette.glassFallback)
        }
    }
}
