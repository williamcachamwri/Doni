import SwiftUI

/// Apple's material, reached only through `#available`.
///
/// The deployment target is iOS 17, so `glassEffect` cannot be applied unconditionally: on an
/// older device the shell falls back to Telegram's own measured blurred bar colour
/// (`rootNav.blurredBackground`, `#1d1d1d` at 0.9 by dark) over a thin material, which is the
/// nearest thing to what the reference actually draws.
public enum TelegramGlassStyle: Sendable {
    /// A plain capsule — a tab-bar selection, a chip.
    case capsule
    /// A capsule lit by a colour, i.e. the row that is playing or the chip that is on.
    case tintedCapsule(Color)
    /// A plain circle — the photo's search control, which is a glass item of 64 pt rather than a
    /// slot inside the bar.
    case circle
    /// A circle lit by a colour: the tab that is chosen, whose glass reads blue (`#304562`).
    case tintedCircle(Color)
    /// The pill a search field sits in.
    case field
}

extension View {
    /// Liquid Glass where the OS has it, Telegram's measured blur where it does not.
    @ViewBuilder
    public func telegramGlass(_ style: TelegramGlassStyle, fallback: Color) -> some View {
        switch style {
        case .capsule:
            glassed(in: Capsule(), tint: nil, fallback: fallback)
        case let .tintedCapsule(tint):
            glassed(in: Capsule(), tint: tint, fallback: fallback)
        case .circle:
            glassed(in: Circle(), tint: nil, fallback: fallback)
        case let .tintedCircle(tint):
            glassed(in: Circle(), tint: tint, fallback: fallback)
        case .field:
            glassed(
                in: RoundedRectangle(cornerRadius: TelegramLibraryMetrics.searchCornerRadius,
                                     style: .continuous),
                tint: nil,
                fallback: fallback
            )
        }
    }

    @ViewBuilder
    private func glassed<S: Shape>(in shape: S, tint: Color?, fallback: Color) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if let tint {
                // A tinted capsule is also the one you can press, so it gets `interactive`, which
                // is what makes Apple's glass brighten under a finger.
                glassEffect(.regular.interactive().tint(tint.opacity(0.6)), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            self.background(fallback, in: shape)
                .background(.ultraThinMaterial, in: shape)
        }
    }
}
