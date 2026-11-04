import SwiftUI
import TelegramDesignSystem

/// One round glass action at the header's trailing edge.
struct HeaderAction {
    let symbol: String
    let label: String
    let run: () -> Void
}

/// The tab screens' header after the Apple Music set: the title set left in `bold(34)` and round
/// glass actions beside it, the list scrolling under both.
///
/// It replaces the floating pill on those screens — a pill centring its title fought a title this
/// wide, and the screens the user pointed at carry no pill at all. The header pins to the top of
/// the screen with an opaque background, so rows vanish behind it the way they do behind the
/// reference's own bars.
struct LargeTitleHeader: View {
    let title: String
    var actions: [HeaderAction] = []

    private let palette = TelegramPalette.dark

    var body: some View {
        HStack(spacing: TelegramHeaderMetrics.actionGap) {
            Text(title)
                .font(TelegramShellTypography.largeTitle)
                .foregroundStyle(palette.navPrimaryText)
                .lineLimit(1)
            Spacer(minLength: TelegramHeaderMetrics.actionGap)
            ForEach(actions, id: \.label) { action in
                Button(action: action.run) {
                    Image(systemName: action.symbol)
                        .font(.system(size: TelegramHeaderMetrics.actionGlyph, weight: .medium))
                        .foregroundStyle(palette.navPrimaryText)
                        .frame(width: TelegramHeaderMetrics.actionCircle,
                               height: TelegramHeaderMetrics.actionCircle)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .telegramGlass(.circle, fallback: palette.glassFallback)
                .accessibilityLabel(action.label)
            }
        }
        .padding(.horizontal, TelegramHeaderMetrics.sideInset)
        .padding(.top, TelegramHeaderMetrics.topPadding)
        .padding(.bottom, TelegramHeaderMetrics.bottomPadding)
        .background(palette.chatListBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
