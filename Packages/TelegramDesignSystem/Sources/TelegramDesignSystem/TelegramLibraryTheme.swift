import SwiftUI

/// Geometry two screens draw the same way: a rule one *physical* pixel wide.
///
/// `separatorHeight = 1.0 / UIScreen.main.scale` (`ChatListItem.swift:928`); the login
/// screens reach the same number through `ItemListSeparatorNode`. A 1 pt rule would read
/// visibly heavier at @3x.
public enum TelegramGeometry {
    public static func hairline(displayScale: CGFloat) -> CGFloat { 1.0 / max(1.0, displayScale) }
}

/// Typography and geometry of a chat-list row, at Telegram's default
/// `itemListBaseFontSize` of 17. Every number cites the line that draws it in
/// `Docs/design-tokens.md`, "Chat list — the clothing the library wears".
public enum TelegramLibraryMetrics {
    /// `4L − 8` with `L = 19`, the line box of `semibold(16)` (`ChatListItem.swift:4042-4051`).
    public static let rowHeight: CGFloat = 68
    /// The chat list centres its 60 pt avatar (`:4208`); a 44 pt play circle takes the same
    /// centre, so it starts 12 pt down.
    public static let playTop: CGFloat = 12
    /// `rawContentRect.origin.y = 8` with `layoutOffset` at zero (`:3671`, `:4054`).
    public static let titleTop: CGFloat = 8
    /// The timestamp frame is the content frame two points lower (`:4556`).
    public static let dateTop: CGFloat = 10
    /// The preview sits two points inside the title's line box (`:4766`).
    public static let titleToPreview: CGFloat = -2

    /// `avatarLeftEdgeInset` (`:2560`) — the icon column's left edge.
    public static let leading: CGFloat = 16
    /// `edge + 8.0 + diameter` (`:2567`), and the same 8 pt gap after the file row's
    /// 44 pt control (`ChatMessageInteractiveFileNode.swift:744`).
    public static let iconToText: CGFloat = 8
    /// `progressDiameter` (`ChatMessageInteractiveFileNode.swift:858`).
    public static let playDiameter: CGFloat = 44
    /// The timestamp's right edge lands here (`:4556`), and so does the rule (`:5378`).
    public static let trailing: CGFloat = 16
    /// `params.width − leftInset − rightInset − 18.0` (`:3673`) — the least the preview may
    /// be squeezed to before the timestamp is measured against it (`:3849`).
    public static let minGapToTimestamp: CGFloat = 18

    public static let navigationBarHeight: CGFloat = 44
    /// `SearchBarStyle.height` for `.modern` (`SearchBarNode.swift:859-870`).
    public static let searchFieldHeight: CGFloat = 36
    /// `cornerDiameter / 2.0` (`:848-856`, applied at `:1045`).
    public static let searchCornerRadius: CGFloat = 21.0 / 2.0
    /// `SearchBarStyle.padding` (`:872-883`).
    public static let searchPadding: CGFloat = 10
    /// The field's bottom sits ten points above the bar's rule, which is what
    /// `verticalOffset = boundingSize.height − 82.0` works out to (`:1179`, `:1187`).
    public static let searchBelow: CGFloat = 10
    /// Loupe five points inside the pill, text twenty-four (`:1203-1205`, `:1195`, `:1200`).
    public static let loupeInset: CGFloat = 5
    public static let loupeSide: CGFloat = 14
    public static let fieldTextInset: CGFloat = 24
    /// The clear button's column (`:1195`).
    public static let clearWidth: CGFloat = 27

    /// Telegram's audio row glyph is a native asset (`Media/Message Audio Play`), so the
    /// triangle's point size is the one number here measured off a render rather than a line.
    public static let playGlyph: CGFloat = 15
    public static let downloadGlyph: CGFloat = 15
}

/// The list's fonts, straight from the calls that set them.
public enum TelegramLibraryTypography {
    /// `Font.semibold(floor(base × 16/17))` — the peer name (`ChatListItem.swift:2289`).
    public static let title = Font.system(size: 16, weight: .semibold)
    /// `Font.regular(floor(base × 15/17))` — the preview (`:2290`).
    public static let preview = Font.system(size: 15, weight: .regular)
    /// `Font.regular(floor(base × 14/17))` — the timestamp (`:2292`).
    public static let date = Font.system(size: 14, weight: .regular)
    /// `Font.with(size: 17, weight: .semibold, traits: [.monospacedNumbers])` — the bar
    /// title (`ChatTitleView.swift:26`), and `regular(13)` under it (`:27`).
    public static let barTitle = Font.system(size: 17, weight: .semibold)
    public static let barSubtitle = Font.system(size: 13, weight: .regular)
    /// `Font.regular(17.0)` for `.modern` (`SearchBarNode.swift:839-846`).
    public static let searchField = Font.system(size: 17, weight: .regular)
}
