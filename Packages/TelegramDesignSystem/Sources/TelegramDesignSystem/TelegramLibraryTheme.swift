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

    /// The chat list's own scaled icon side, `floor(base × 54/17)` (`:4212`). A cover takes the
    /// avatar slot; a 44 pt play control is too small to hold artwork.
    public static let artSide: CGFloat = 54
    /// `floor((itemHeight − diameter) / 2)` — how the avatar is centred in the cell (`:4208`).
    public static let artTop: CGFloat = floor((rowHeight - artSide) / 2)
    /// `.roundedRect` clipping is `floor(width × 0.25)` (`PeerAvatar.swift:209`), not a circle:
    /// a square cover inscribed in a circle loses its corners.
    public static let artRadius: CGFloat = floor(artSide * 0.25)
    /// Album art gets Telegram's own darkening: 0.3 is the scrim `playerAlbumArt` draws under
    /// its controls (`ChatMessageInteractiveFileNode.swift:1815`). Nothing sits on this tile, so
    /// it takes a quarter of that — enough to even out a bright cover, not enough to muddy it.
    public static let artScrim: Double = 0.3 / 4.0
    /// The note on a coverless track, between the 9 pt state glyph and the 16 pt title.
    public static let artGlyph: CGFloat = 18

    /// `avatarLeftEdgeInset` (`:2560`) — the icon column's left edge.
    public static let leading: CGFloat = 16
    /// `textLeftInset` is 84 (`:2567`) whatever stands in the icon column, so the gap after a
    /// 54 pt tile is what is left of it.
    public static let artToText: CGFloat = 84 - leading - artSide
    /// The timestamp's right edge lands here (`:4556`), and so does the rule (`:5378`).
    public static let trailing: CGFloat = 16
    /// `params.width − leftInset − rightInset − 18.0` (`:3673`) — the least the preview may be
    /// squeezed to before the timestamp is measured against it (`:3849`).
    public static let minGapToTimestamp: CGFloat = 18

    /// `rawContentRect.origin.y = 8` with `layoutOffset` at zero (`:3671`, `:4054`).
    public static let titleTop: CGFloat = 8
    /// The preview sits two points inside the title's line box (`:4766`).
    public static let titleToPreview: CGFloat = -2
    /// The timestamp frame is the content frame two points lower (`:4556`).
    public static let dateTop: CGFloat = 10

    /// The chat list's second right-hand slot — the unread bubble — carries the download state
    /// here. `badgeDiameter = floor(base × 20.0/17.0)` (`ChatListItem.swift:2578`), and a bubble
    /// with no count in it is a plain square of that side: `badgeWidth = imageWidth`, returned
    /// as `CGSize(width: badgeWidth, height: imageWidth)` (`ChatListBadgeNode.swift:89`, `:94`).
    public static let stateSide: CGFloat = 20
    /// Telegram's audio-row play triangle is a native asset (`Media/Message Audio Play`), so the
    /// glyph inside the bubble is measured off a render rather than off a line.
    public static let stateGlyph: CGFloat = 9

    /// Doni's own: the chat list has no heart in a row, so this has nothing to be quoted from. It
    /// is 12 pt because it shares the column's first line with `regular(14)` (`:2292`) and a mark
    /// taller than the number beside it reads as the column's subject rather than its note.
    public static let favoriteMark: CGFloat = 12

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
    /// The clear button is scaled to 0.2 when hidden and 1.0 when shown, not faded (`:1647`).
    public static let clearHiddenScale: CGFloat = 0.2
}

/// The list's fonts, straight from the calls that set them.
public enum TelegramLibraryTypography {
    /// `Font.semibold(floor(base × 16/17))` — the peer name (`ChatListItem.swift:2289`).
    public static let title = Font.system(size: 16, weight: .semibold)
    /// `Font.regular(floor(base × 15/17))` — the preview (`:2290`).
    public static let preview = Font.system(size: 15, weight: .regular)
    /// `Font.regular(floor(base × 14/17))` — the timestamp (`:2292`).
    public static let date = Font.system(size: 14, weight: .regular)
    /// A duration is a number that has to line up down the column, so it gets the tabular
    /// digits Telegram puts on its bar title (`ChatTitleView.swift:26`,
    /// `traits: [.monospacedNumbers]`) and on a file's size (`ChatMessageInteractiveFileNode.swift:579`).
    public static let duration = Font.system(size: 14, weight: .regular).monospacedDigit()
    /// `Font.with(size: 17, weight: .semibold, traits: [.monospacedNumbers])` — the bar
    /// title (`ChatTitleView.swift:26`), and `regular(13)` under it (`:27`).
    public static let barTitle = Font.system(size: 17, weight: .semibold)
    public static let barSubtitle = Font.system(size: 13, weight: .regular)
    /// `Font.regular(17.0)` for `.modern` (`SearchBarNode.swift:839-846`).
    public static let searchField = Font.system(size: 17, weight: .regular)
}

/// A track with no cover tag still gets colour, and it gets it the way Telegram colours
/// avatars: seven gradient pairs, picked by id, drawn vertically with the lighter stop on top.
///
/// `AvatarNode.swift:322-330` is the palette, `PeerAvatar.swift:403-424` the pick
/// (`abs(id) % gradientColors.count`), `:426` the `locations [1.0, 0.0]` that puts the second
/// colour above the first.
public enum TelegramTrackGradient {
    /// `AvatarNode.gradientColors`, in Telegram's order: red, orange, purple, green, cyan,
    /// blue, violet.
    public static let pairs: [(bottom: Color, top: Color)] = [
        (Color(rgb: 0xff516a), Color(rgb: 0xff885e)),
        (Color(rgb: 0xffa85c), Color(rgb: 0xffcd6a)),
        (Color(rgb: 0x665fff), Color(rgb: 0x82b1ff)),
        (Color(rgb: 0x54cb68), Color(rgb: 0xa0de7e)),
        (Color(rgb: 0x4acccd), Color(rgb: 0x00fcfd)),
        (Color(rgb: 0x2a9ef1), Color(rgb: 0x72d5fd)),
        (Color(rgb: 0xd669ed), Color(rgb: 0xe0a2f3))
    ]

    /// Telegram picks by numeric id (`PeerAvatar.swift:403-409`); a track's stable number is
    /// the message it came from.
    public static func index(for seed: Int64) -> Int {
        // `abs(Int64.min)` traps, so the one value that cannot be made positive is folded
        // to the largest that can.
        let magnitude = seed == .min ? Int64.max : abs(seed)
        return Int(magnitude % Int64(pairs.count))
    }

    /// `locations = [1.0, 0.0]` puts the second colour at the top (`PeerAvatar.swift:426`).
    public static func linear(_ seed: Int64) -> LinearGradient {
        let pair = pairs[index(for: seed)]
        return LinearGradient(colors: [pair.bottom, pair.top], startPoint: .bottom, endPoint: .top)
    }
}
