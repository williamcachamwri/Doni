import SwiftUI

/// Apple's material, reached only through `#available`.
///
/// The deployment target is iOS 17, so `glassEffect` cannot be applied unconditionally: on an
/// older device the shell falls back to Telegram's own measured blurred bar colour
/// (`rootNav.blurredBackground`, `#1d1d1d` at 0.9 by dark) over a thin material, which is the
/// nearest thing to what the reference actually draws.
public enum TelegramGlassStyle: Sendable {
    /// A plain capsule — a tab-bar selection, a chip, the bar pill itself.
    case capsule
    /// A plain circle — the photo's search control, which is a glass item of 64 pt rather than a
    /// slot inside the bar.
    case circle
    /// The pill a search field sits in.
    case field
}

extension View {
    /// Liquid Glass where the OS has it, Telegram's measured blur where it does not.
    @ViewBuilder
    public func telegramGlass(_ style: TelegramGlassStyle, fallback: Color) -> some View {
        switch style {
        case .capsule:
            glassed(in: Capsule(), fallback: fallback)
        case .circle:
            glassed(in: Circle(), fallback: fallback)
        case .field:
            glassed(
                in: RoundedRectangle(cornerRadius: TelegramLibraryMetrics.searchCornerRadius,
                                     style: .continuous),
                fallback: fallback
            )
        }
    }

    @ViewBuilder
    private func glassed<S: Shape>(in shape: S, fallback: Color) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(fallback, in: shape)
                .background(.ultraThinMaterial, in: shape)
        }
    }
}
