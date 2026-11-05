import SwiftUI

/// Colour tokens transcribed from the Telegram-iOS reference as *values*; every entry cites the
/// `file:line` in `Docs/design-tokens.md` and none of its code is copied here. Doni is a dark app — the
/// day values are kept because the login screens were measured on the day theme.
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
    /// `DefaultDayPresentationTheme.swift:452`.
    public let searchClearButton: Color
    /// `rootNav.opaqueBackground`, `#f7f7f7` mixed with white at 0.14 → `#f8f8f8` (`:420`).
    public let navOpaqueBackground: Color
    /// `messages.mediaActiveControlColor` / `mediaInactiveControlColor` — the audio row's played and idle
    /// states: day `:632`/`:633`, dark `:559`.
    public let mediaActiveControl: Color
    public let mediaInactiveControl: Color
    /// The glyph inside those controls, `messages.mediaControlInnerBackgroundColor`: white on a blue
    /// bubble by day (`:634`), `#262628` on a white one by dark (`:559`).
    public let mediaControlGlyph: Color
    /// `rootNav.blurredBackground` — the bar is a blur, not a fill, so content reads through it (day
    /// `:419`, dark `:345`). `rootTabBar.backgroundColor` is the same colour in both themes (day `:434`,
    /// dark `:359`).
    public let barBlurredBackground: Color
    /// `rootTabBar.selectedIconColor` — by day selection is blue, by dark it is weight and the glass
    /// capsule alone (day `:437`, dark `:363`).
    public let tabBarSelectedIcon: Color
    /// `rootTabBar.textColor` (day `:438`, dark `:364`).
    public let tabBarText: Color
    /// `list.modalPlainBackgroundColor` — a pushed screen is a lighter black than the list it
    /// came from (day `:476`, dark `:416`).
    public let listModalBackground: Color
    /// `list.itemPrimaryTextColor` / `itemSecondaryTextColor` (day `:477`/`:478`, dark `:417`/`:418`).
    public let listPrimaryText: Color
    public let listSecondaryText: Color
    /// `list.itemDestructiveColor` (day `:482`, dark `:422`).
    public let listDestructive: Color
    /// `rootNav.segmentedBackgroundColor` / `segmentedForegroundColor` / `segmentedDividerColor`
    /// (day `:425`, `:426`, `:428`; dark `:351`, `:352`, `:353`).
    public let segmentedFill: Color
    public let segmentedSelected: Color
    public let segmentedDivider: Color
    /// `chatList.unreadBadgeActiveBackgroundColor` / `…TextColor` (day `:559`/`:560`,
    /// dark `:499`/`:500`). A dark unread bubble is a white pill with black digits.
    public let unreadBadgeFill: Color
    public let unreadBadgeText: Color
    /// `chatList.unreadBadgeInactiveBackgroundColor` / `…TextColor` (day `:561`/`:562`,
    /// dark `:501`/`:502`) — the *muted* bubble, which Doni borrows for a track whose file is not on
    /// the phone: the photo's grey pill measures `#666666` at 3x with black digits inside.
    public let unreadBadgeInactiveFill: Color
    public let unreadBadgeInactiveText: Color
    /// What a Liquid Glass capsule reads as on this screen: the photo's bar and tab capsules measure
    /// `#3e3e40` inside with a `#686869` rim (`box`/`vedges` at y 172…302 px) — what `glassEffect(.regular)`
    /// composites to over the app's black. Without Liquid Glass the shell paints this, under a thin
    /// material.
    public let glassFallback: Color
    /// Doni's own blue, for what the app lights up: a matched run, the playing row, the selected chip,
    /// the glass capsule's tint. It is Telegram's colour-customised dark accent
    /// (`DefaultDarkPresentationTheme.swift:7`), so the hue already sits in the theme file.
    public let highlight: Color

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
        searchPlaceholder: Color,
        searchClearButton: Color,
        navOpaqueBackground: Color,
        mediaActiveControl: Color,
        mediaInactiveControl: Color,
        mediaControlGlyph: Color,
        barBlurredBackground: Color,
        tabBarSelectedIcon: Color,
        tabBarText: Color,
        listModalBackground: Color,
        listPrimaryText: Color,
        listSecondaryText: Color,
        listDestructive: Color,
        segmentedFill: Color,
        segmentedSelected: Color,
        segmentedDivider: Color,
        unreadBadgeFill: Color,
        unreadBadgeText: Color,
        unreadBadgeInactiveFill: Color,
        unreadBadgeInactiveText: Color,
        glassFallback: Color,
        highlight: Color
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
        self.searchClearButton = searchClearButton
        self.navOpaqueBackground = navOpaqueBackground
        self.mediaActiveControl = mediaActiveControl
        self.mediaInactiveControl = mediaInactiveControl
        self.mediaControlGlyph = mediaControlGlyph
        self.barBlurredBackground = barBlurredBackground
        self.tabBarSelectedIcon = tabBarSelectedIcon
        self.tabBarText = tabBarText
        self.listModalBackground = listModalBackground
        self.listPrimaryText = listPrimaryText
        self.listSecondaryText = listSecondaryText
        self.listDestructive = listDestructive
        self.segmentedFill = segmentedFill
        self.segmentedSelected = segmentedSelected
        self.segmentedDivider = segmentedDivider
        self.unreadBadgeFill = unreadBadgeFill
        self.unreadBadgeText = unreadBadgeText
        self.unreadBadgeInactiveFill = unreadBadgeInactiveFill
        self.unreadBadgeInactiveText = unreadBadgeInactiveText
        self.glassFallback = glassFallback
        self.highlight = highlight
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
        searchPlaceholder: Color(rgb: 0x8e8e93),
        searchClearButton: Color(rgb: 0x7b7b81),
        navOpaqueBackground: Color(rgb: 0xf8f8f8),
        mediaActiveControl: Color(rgb: 0x0088ff),
        mediaInactiveControl: Color(rgb: 0xcacaca),
        mediaControlGlyph: Color(rgb: 0xffffff),
        barBlurredBackground: Color(rgb: 0xf2f2f2, alpha: 0.9),
        tabBarSelectedIcon: Color(rgb: 0x0088ff),
        tabBarText: Color(rgb: 0x000000, alpha: 0.8),
        listModalBackground: Color(rgb: 0xffffff),
        listPrimaryText: Color(rgb: 0x000000),
        listSecondaryText: Color(rgb: 0x8e8e93),
        listDestructive: Color(rgb: 0xff3b30),
        segmentedFill: Color(rgb: 0x000000, alpha: 0.06),
        segmentedSelected: Color(rgb: 0xf7f7f7),
        segmentedDivider: Color(rgb: 0xd6d6dc),
        unreadBadgeFill: Color(rgb: 0x0088ff),
        unreadBadgeText: Color(rgb: 0xffffff),
        unreadBadgeInactiveFill: Color(rgb: 0xb6b6bb),
        unreadBadgeInactiveText: Color(rgb: 0xffffff),
        glassFallback: Color(rgb: 0xf2f2f2, alpha: 0.9),
        highlight: Color(rgb: 0x0088ff)
    )

    /// `DefaultDarkPresentationTheme.swift` — the mode Doni ships in. The accent here is white, not blue:
    /// Telegram's *plain* dark theme makes its accent white (`:344`, `:420`) and `#3e88f7` exists only in
    /// the colour-customised variant (`:7`). Doni keeps both — white where Telegram puts white, blue
    /// where the app lights something up.
    public static let dark = TelegramPalette(
        accent: Color(rgb: 0xffffff),
        chatListBackground: Color(rgb: 0x000000),
        chatListSeparator: Color(rgb: 0x545458, alpha: 0.55),
        chatListItemHighlighted: Color(rgb: 0x121212),
        chatListItemSelected: Color(rgb: 0x191919),
        chatListPinnedItemBackground: Color(rgb: 0x1c1c1d),
        chatListTitle: Color(rgb: 0xffffff),
        chatListDateText: Color(rgb: 0x8d8e93),
        chatListMessageText: Color(rgb: 0x8d8e93),
        chatListDraftText: Color(rgb: 0xeb5545),
        navPrimaryText: Color(rgb: 0xffffff),
        navSecondaryText: Color(rgb: 0xffffff, alpha: 0.5),
        navControl: Color(rgb: 0x767676),
        navSeparator: Color(rgb: 0x545458, alpha: 0.55),
        navBadge: Color(rgb: 0xffffff),
        tabBarSeparator: Color(rgb: 0x545458, alpha: 0.55),
        tabBarIcon: Color(rgb: 0xffffff),
        searchInputFill: Color(rgb: 0xffffff, alpha: 0.1),
        searchPlaceholder: Color(rgb: 0x8f8f8f),
        searchClearButton: Color(rgb: 0x8f8f8f),
        navOpaqueBackground: Color(rgb: 0x1a1a1a),
        mediaActiveControl: Color(rgb: 0xffffff),
        mediaInactiveControl: Color(rgb: 0xffffff, alpha: 0.4),
        mediaControlGlyph: Color(rgb: 0x262628),
        barBlurredBackground: Color(rgb: 0x1d1d1d, alpha: 0.9),
        tabBarSelectedIcon: Color(rgb: 0xffffff),
        tabBarText: Color(rgb: 0xffffff),
        listModalBackground: Color(rgb: 0x1c1c1d),
        listPrimaryText: Color(rgb: 0xffffff),
        listSecondaryText: Color(rgb: 0x98989e),
        listDestructive: Color(rgb: 0xeb5545),
        segmentedFill: Color(rgb: 0xffffff, alpha: 0.11),
        segmentedSelected: Color(rgb: 0xffffff, alpha: 0.36),
        segmentedDivider: Color(rgb: 0x505155),
        unreadBadgeFill: Color(rgb: 0xffffff),
        unreadBadgeText: Color(rgb: 0x000000),
        unreadBadgeInactiveFill: Color(rgb: 0x666666),
        unreadBadgeInactiveText: Color(rgb: 0x000000),
        glassFallback: Color(rgb: 0x3e3e40),
        highlight: Color(rgb: 0x3e88f7)
    )
}

/// Splits a `0xRRGGBB` literal into sRGB components, outside the initialiser so the bit arithmetic is
/// testable without a UI framework.
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
    /// Telegram's `UIColor(rgb:)` takes a `UInt32` literal in sRGB, so the same number has to resolve in
    /// sRGB here: the default `Color(red:…)` is not guaranteed sRGB and shifts every hue slightly.
    public init(rgb: UInt32, alpha: Double = 1.0) {
        let c = SRGBComponents(rgb: rgb, alpha: alpha)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}
