import SwiftUI

/// `theme.list.*` — the colours the authorization screens read.
///
/// Login is not a chat screen: `AuthorizationSequenceController` sets its background to
/// `list.plainBackgroundColor` and every node on it takes its text colour from the same
/// `list.*` block. Sources are the line numbers in `Docs/design-tokens.md`,
/// "Palette — day, `list.*`".
public struct TelegramListPalette: Sendable {
    public let background: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let disabledText: Color
    public let accent: Color
    public let destructive: Color
    public let placeholder: Color
    public let separator: Color
    public let checkFill: Color
    public let checkForeground: Color
    /// `plainBackground` mixed with `disabledText` at 0.15, which `SolidRoundedButtonTheme`
    /// uses for a disabled button. 255·0.85 + 142·0.15 ≈ 238 per channel, so `#eeeeee`.
    public let disabledCheckFill: Color

    public init(
        background: Color,
        primaryText: Color,
        secondaryText: Color,
        disabledText: Color,
        accent: Color,
        destructive: Color,
        placeholder: Color,
        separator: Color,
        checkFill: Color,
        checkForeground: Color,
        disabledCheckFill: Color
    ) {
        self.background = background
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.disabledText = disabledText
        self.accent = accent
        self.destructive = destructive
        self.placeholder = placeholder
        self.separator = separator
        self.checkFill = checkFill
        self.checkForeground = checkForeground
        self.disabledCheckFill = disabledCheckFill
    }

    public static let day = TelegramListPalette(
        background: Color(rgb: 0xffffff),
        primaryText: Color(rgb: 0x000000),
        secondaryText: Color(rgb: 0x8e8e93),
        disabledText: Color(rgb: 0x8e8e93),
        accent: Color(rgb: 0x0088ff),
        destructive: Color(rgb: 0xff3b30),
        placeholder: Color(rgb: 0xc8c8ce),
        separator: Color(rgb: 0xc8c7cc),
        checkFill: Color(rgb: 0x0088ff),
        checkForeground: Color(rgb: 0xffffff),
        disabledCheckFill: Color(rgb: 0xeeeeee)
    )
}

/// Typography of the authorization screens, in Telegram's own weights.
///
/// The weight is part of the token: `Font.light(30.0)` is the phone title with the keyboard
/// closed and `Font.bold(28.0)` is the same label once it opens, so a single `.title` would
/// be wrong in both states.
public enum TelegramLoginTypography {
    public static let phoneTitleIdle = Font.system(size: 30, weight: .light)
    public static let phoneTitleActive = Font.system(size: 28, weight: .bold)
    public static let title = Font.system(size: 28, weight: .semibold)
    public static let subtitle = Font.system(size: 17, weight: .regular)
    /// 20 pt is what the dial code, the number and the password are typed at.
    public static let field = Font.system(size: 20, weight: .regular)
    public static let link = Font.system(size: 17, weight: .regular)
    public static let footnote = Font.system(size: 13, weight: .regular)
    public static let digit = Font.system(size: 23, weight: .regular, design: .monospaced)
    public static let digitCompact = Font.system(size: 20, weight: .regular, design: .monospaced)
    public static let buttonTitle = Font.system(size: 15, weight: .bold, design: .rounded)
}

/// Geometry of the authorization screens. See "Login (authorization sequence)" in
/// `Docs/design-tokens.md` for the line each number was read from.
public enum TelegramLoginMetrics {
    public static let horizontalInset: CGFloat = 24
    public static let topInset: CGFloat = 18
    public static let titleToSubtitle: CGFloat = 18
    public static let subtitleToField: CGFloat = 30
    public static let fieldToResend: CGFloat = 50
    /// Gap between the button and the top of the keyboard, or the safe area without one.
    public static let buttonToBottom: CGFloat = 24
    public static let buttonHeight: CGFloat = 50
    public static let buttonCornerRadius: CGFloat = 25

    public static let countryRowHeight: CGFloat = 57
    public static let numberRowHeight: CGFloat = 58
    /// Both rows sit at their own offset, not at the content inset: the dial code is
    /// 18 pt from the screen edge and the digits 107 pt, so the columns line up under
    /// the mask Telegram draws them with.
    public static let dialCodeLeading: CGFloat = 18
    public static let numberLeading: CGFloat = 107
    /// The country title is inset a further 16 inside the content band.
    public static let countryLeading: CGFloat = 40
    public static let countryChevronWidth: CGFloat = 10
    public static let plainFieldHeight: CGFloat = 44

    public static let codeBoxWidth: CGFloat = 43
    public static let codeBoxHeight: CGFloat = 51
    public static let codeBoxCompactWidth: CGFloat = 37
    public static let codeBoxCompactHeight: CGFloat = 44
    public static let codeBoxSpacing: CGFloat = 15
    public static let codeBoxCornerRadius: CGFloat = 15

    /// Telegram draws its rules and box borders one *physical* pixel wide, so the point
    /// width depends on the display: 1 pt would read visibly heavier at @3x.
    public static func hairline(displayScale: CGFloat) -> CGFloat { 1.0 / max(1.0, displayScale) }
}
