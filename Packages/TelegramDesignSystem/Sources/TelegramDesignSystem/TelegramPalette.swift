import SwiftUI

/// Colour tokens transcribed from the Telegram-iOS reference as *values*.
/// Every entry cites the `file:line` it was read from in `Docs/design-tokens.md`;
/// the reference checkout is read-only and none of its code is copied here.
///
/// Only the day palette is filled in so far. The dark palette is extracted per
/// screen when that screen's parity pass happens (M4) rather than guessed by
/// mirroring the day numbers.
public struct TelegramPalette: Sendable {
    public let accent: Color
    public let chatListBackground: Color
    public let chatListSeparator: Color
    public let chatListItemHighlighted: Color
    public let chatListItemSelected: Color
    public let chatListPinnedItemBackground: Color
    public let chatListTitle: Color
    public let chatListDateText: Color
    public let chatListMessageText: Color
    public let chatListDraftText: Color
    public let navPrimaryText: Color
    public let navSecondaryText: Color
    public let navControl: Color
    public let navSeparator: Color
    public let navBadge: Color
    public let tabBarSeparator: Color
    public let tabBarIcon: Color
    public let searchInputFill: Color
    public let searchPlaceholder: Color

    public init(
        accent: Color,
        chatListBackground: Color,
        chatListSeparator: Color,
        chatListItemHighlighted: Color,
        chatListItemSelected: Color,
        chatListPinnedItemBackground: Color,
        chatListTitle: Color,
        chatListDateText: Color,
        chatListMessageText: Color,
        chatListDraftText: Color,
        navPrimaryText: Color,
        navSecondaryText: Color,
        navControl: Color,
        navSeparator: Color,
        navBadge: Color,
        tabBarSeparator: Color,
        tabBarIcon: Color,
        searchInputFill: Color,
        searchPlaceholder: Color
    ) {
        self.accent = accent
        self.chatListBackground = chatListBackground
        self.chatListSeparator = chatListSeparator
        self.chatListItemHighlighted = chatListItemHighlighted
        self.chatListItemSelected = chatListItemSelected
        self.chatListPinnedItemBackground = chatListPinnedItemBackground
        self.chatListTitle = chatListTitle
        self.chatListDateText = chatListDateText
        self.chatListMessageText = chatListMessageText
        self.chatListDraftText = chatListDraftText
        self.navPrimaryText = navPrimaryText
        self.navSecondaryText = navSecondaryText
        self.navControl = navControl
        self.navSeparator = navSeparator
        self.navBadge = navBadge
        self.tabBarSeparator = tabBarSeparator
        self.tabBarIcon = tabBarIcon
        self.searchInputFill = searchInputFill
        self.searchPlaceholder = searchPlaceholder
    }

    /// `DefaultDayPresentationTheme.swift` in the reference checkout.
    public static let day = TelegramPalette(
        accent: Color(rgb: 0x0088ff),
        chatListBackground: Color(rgb: 0xffffff),
        chatListSeparator: Color(rgb: 0xc8c7cc),
        chatListItemHighlighted: Color(rgb: 0xe5e5ea),
        chatListItemSelected: Color(rgb: 0xe9f0fa),
        chatListPinnedItemBackground: Color(rgb: 0xf7f7f7),
        chatListTitle: Color(rgb: 0x000000),
        chatListDateText: Color(rgb: 0x8e8e93),
        chatListMessageText: Color(rgb: 0x8e8e93),
        chatListDraftText: Color(rgb: 0xdd4b39),
        navPrimaryText: Color(rgb: 0x000000),
        navSecondaryText: Color(rgb: 0x787878),
        navControl: Color(rgb: 0x7e8791),
        navSeparator: Color(rgb: 0xc8c7cc),
        navBadge: Color(rgb: 0xff3b30),
        tabBarSeparator: Color(rgb: 0xb2b2b2),
        tabBarIcon: Color(rgb: 0x959595),
        searchInputFill: Color(rgb: 0x000000, alpha: 0.06),
        searchPlaceholder: Color(rgb: 0x8e8e93)
    )

    /// `DefaultDarkPresentationTheme.swift:7`.
    public static let darkAccent = Color(rgb: 0x3e88f7)
}

/// Splits a `0xRRGGBB` literal into sRGB components. Broken out of the
/// initialiser so the bit arithmetic is testable without a UI framework.
public struct SRGBComponents: Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(rgb: UInt32, alpha: Double = 1.0) {
        self.red = Double((rgb >> 16) & 0xff) / 255.0
        self.green = Double((rgb >> 8) & 0xff) / 255.0
        self.blue = Double(rgb & 0xff) / 255.0
        self.alpha = alpha
    }
}

extension Color {
    /// Telegram's `UIColor(rgb:)` takes a `UInt32` literal in sRGB, so the same
    /// number has to resolve in sRGB here; the default `Color(red:…)` is not
    /// guaranteed to be sRGB and would shift every hue slightly.
    public init(rgb: UInt32, alpha: Double = 1.0) {
        let c = SRGBComponents(rgb: rgb, alpha: alpha)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}
