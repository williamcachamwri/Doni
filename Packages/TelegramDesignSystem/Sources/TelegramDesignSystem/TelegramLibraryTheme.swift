import SwiftUI

/// Geometry two screens draw the same way: a rule one *physical* pixel wide.
///
/// `separatorHeight = 1.0 / UIScreen.main.scale` (`ChatListItem.swift:928`); the login
/// screens reach the same number through `ItemListSeparatorNode`. A 1 pt rule would read
/// visibly heavier at @3x.
public enum TelegramGeometry {
    public static func hairline(displayScale: CGFloat) -> CGFloat { 1.0 / max(1.0, displayScale) }
}

/// Typography and geometry of a chat-list row, at the scale the reference *phone* is drawn at.
///
/// The source files are written at Telegram's default `itemListBaseFontSize` of 17, and the
/// sections above quote them; the photo in "The screenshot oracle" says the phone is not at 17. It
/// is at Telegram's smallest size, and three independent measurements agree: the pitch is 56 pt
/// rather than 68, the icon column is 49 pt rather than 60, and the title ink is 9.0–10.0 pt rather
/// than 11.7. So every scaled number below is `floor(14 × n / 17)` — the same expression the
/// reference uses, evaluated at the size the app is really set to.
public enum TelegramLibraryMetrics {
    /// `PresentationFontSize.extraSmall.baseDisplaySize` (`ComponentsThemes.swift:21`) and
    /// `ItemListItem.itemListBaseFontSize` for the same case (`ItemListItem.swift:176-179`).
    public static let base: CGFloat = 14

    /// Telegram's own scaling expression (`ChatListItem.swift:2289-2294`), kept as a function so
    /// each token cites the ratio it was passed rather than a hand-worked number.
    public static func scaled(_ ratio: CGFloat) -> CGFloat { floor(base * ratio / 17.0) }

    /// The line box of `semibold(13)`, the `L` of the row's own height formula. At 17 this is the
    /// 19 the sections above quote.
    public static let lineHeight: CGFloat = 16
    /// `titleHeight + 3L − 1 − 3 + 8 × 2 + 1 − 21` (`ChatListItem.swift:4042-4051`), which with
    /// `titleHeight = L` is `4L − 8` — and `4 × 16 − 8 = 56` is the pitch the photo measures.
    public static let rowHeight: CGFloat = 4.0 * lineHeight - 8.0

    /// `min(60, floor(base × 60/17))` (`ChatListItem.swift:2559`) — the avatar column, which Doni
    /// spends on a cover. At 17 this is 60; the 54 the previous section quoted is the
    /// inline-navigation scale (`:4212`), not the row's own.
    public static let artSide: CGFloat = min(60, scaled(60))
    /// `floor((itemHeight − diameter) / 2)` — how the avatar is centred in the cell (`:4208`).
    public static let artTop: CGFloat = floor((rowHeight - artSide) / 2)
    /// Album art gets Telegram's own darkening: 0.3 is the scrim `playerAlbumArt` draws under
    /// its controls (`ChatMessageInteractiveFileNode.swift:1815`). Nothing sits on this tile, so
    /// it takes a quarter of that — enough to even out a bright cover, not enough to muddy it.
    public static let artScrim: Double = 0.3 / 4.0
    /// The note on a coverless track: Doni's own, a third of the tile, the ratio 18 held in the
    /// 54 pt column it replaced.
    public static let artGlyph: CGFloat = floor(artSide / 3.0)

    /// `avatarLeftEdgeInset` (`:2560`) — the icon column's left edge.
    public static let leading: CGFloat = 16
    /// `avatarLeftInset = 24.0 + avatarDiameter` (`:2574`) plus the 2 pt `rawContentRect.origin.x`
    /// (`:4054`): where the text column starts. At 17 the same two lines give 86 − 60 = 26 of gap;
    /// the photo's gap is 10.
    public static let textColumnLeft: CGFloat = 24 + artSide + 2
    public static let artToText: CGFloat = textColumnLeft - leading - artSide
    /// `params.rightInset` is zero in the chat list, so `rawContentRect`'s right edge — where the
    /// timestamp and the badge end (`:4556`, `:4625`) and where the rule stops (`:5378`) — is
    /// `width − 16`.
    public static let trailing: CGFloat = 16
    /// `params.width − leftInset − rightInset − 18.0` (`:3673`) — the least the preview may be
    /// squeezed to before the timestamp is measured against it (`:3849`).
    public static let minGapToTimestamp: CGFloat = 18

    /// `rawContentRect.origin.y = floor(base × 8/17)` with `layoutOffset` at zero (`:4054`).
    public static let contentTop: CGFloat = scaled(8)
    /// The title is the top of the content rect — 6 pt from the row's top, not centred in it.
    public static let titleTop: CGFloat = contentTop
    /// The preview sits two points inside the title's line box (`:4766`).
    public static let titleToPreview: CGFloat = -2
    /// `dateFrame.origin.y = contentRect.origin.y + 2.0` (`:4556`).
    public static let dateTop: CGFloat = contentTop + 2

    /// The chat list's second right-hand slot — the unread bubble — carries the download state
    /// here. `badgeDiameter = floor(base × 20.0/17.0)` (`ChatListItem.swift:2578`, passed as
    /// `imageWidth` at `:3677`), and a bubble with no count in it is a plain square of that side:
    /// `badgeWidth = imageWidth`, returned as `CGSize(width: badgeWidth, height: imageWidth)`
    /// (`ChatListBadgeNode.swift:89`, `:94`). The photo's pill is 48 px = 16 pt tall.
    public static let stateSide: CGFloat = scaled(20)
    /// `contentRect.maxY − badgeHeight + rightAccessoryVerticalOffset` (`:4614-4625`), where the
    /// content rect is `itemHeight − 12 − 9` tall (`:4054`) and the offset is
    /// `floorToPixels(−4 × min(1, base/17))` (`:4613`). It works out 21.7 pt below the row's top,
    /// which is where the photo's pill starts (1415 px − 1349 px ÷ 3), and it is an absolute
    /// position rather than a gap: the pill is pinned to the *bottom* of the content rect, not to
    /// the timestamp above it.
    public static let stateTop: CGFloat = contentTop + (rowHeight - 21.0) - stateSide - 4.0 * base / 17.0
    /// `badgeFont = semibold(floor(base × 12/17))` (`:2294`) — the size of what sits in the pill,
    /// whose digits measure 19–20 px of ink.
    public static let stateGlyph: CGFloat = scaled(12)

    /// Doni's own: the chat list has no heart in a row, so this has nothing to be quoted from. It
    /// is one point under the timestamp because it shares that line with `regular(11)` (`:2292`)
    /// and a mark taller than the number beside it reads as the column's subject rather than its
    /// note.
    public static let favoriteMark: CGFloat = 10

    public static let navigationBarHeight: CGFloat = 44
    /// `SearchBarStyle.height` for `.modern` (`SearchBarNode.swift:859-870`). These five are
    /// unscaled literals in the source — the search bar keeps its size whatever the text scale is.
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

/// The list's fonts, from the same calls that set them — `floor(base × n/17)` (`:2289-2294`),
/// evaluated at the photo's base of 14 rather than the source's 17.
public enum TelegramLibraryTypography {
    /// `Font.semibold(floor(base × 16/17))` — the peer name (`ChatListItem.swift:2289`), 13 pt.
    public static let title = Font.system(size: TelegramLibraryMetrics.scaled(16), weight: .semibold)
    /// `Font.regular(floor(base × 15/17))` — the preview (`:2290`), 12 pt.
    public static let preview = Font.system(size: TelegramLibraryMetrics.scaled(15), weight: .regular)
    /// `Font.regular(floor(base × 14/17))` — the timestamp (`:2292`), 11 pt.
    public static let date = Font.system(size: TelegramLibraryMetrics.scaled(14), weight: .regular)
    /// A duration is a number that has to line up down the column, so it gets the tabular
    /// digits Telegram puts on its bar title (`ChatTitleView.swift:26`,
    /// `traits: [.monospacedNumbers]`) and on a file's size (`ChatMessageInteractiveFileNode.swift:579`).
    public static let duration = date.monospacedDigit()
    /// `Font.with(size: 17, weight: .semibold, traits: [.monospacedNumbers])` — the bar
    /// title (`ChatTitleView.swift:26`), and `regular(13)` under it (`:27`). Doni's bars follow the
    /// photo instead, which carries a large centred title; see `TelegramBarMetrics`.
    public static let barTitle = Font.system(size: 17, weight: .semibold)
    public static let barSubtitle = Font.system(size: 13, weight: .regular)
    /// `Font.regular(17.0)` for `.modern` (`SearchBarNode.swift:839-846`) — a literal, unscaled.
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
