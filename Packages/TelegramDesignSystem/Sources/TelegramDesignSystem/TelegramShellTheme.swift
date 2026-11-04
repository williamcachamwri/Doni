import SwiftUI

/// How far a list has to run before its last row clears the floating chrome, handed down from the
/// shell — which owns the strip and therefore knows whether it is showing — to the screens that
/// only own a list.
private struct FloatingClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    public var telegramFloatingClearance: CGFloat {
        get { self[FloatingClearanceKey.self] }
        set { self[FloatingClearanceKey.self] = newValue }
    }
}

/// The shell around the list: a tab bar, a strip of player above it, and the chips Doni uses to
/// pick a channel. Everything the reference draws is quoted from it; the few numbers it does not
/// have are marked Doni's own. `Docs/design-tokens.md`, "Tab bar and the mini player".
///
/// The motion is the one exception that is not Doni's: it is `ChatListBadgeNode.swift`'s own
/// timing, the closest thing in the reference to a state bubble appearing and going away.
public enum TelegramShellMetrics {
    /// Doni's own height: 46 pt of measured artwork with 9 pt of padding above and below.
    /// Telegram's own music panel is 190 (`OverlayAudioPlayerControlsNode.swift:806`) because it
    /// carries the scrubber and the button row as well.
    public static let miniPlayerHeight: CGFloat = 64
    /// `albumArtSize = CGSize(width: 46.0, height: 46.0)` (`:855`).
    public static let miniPlayerArt: CGFloat = 46
    /// `ImageCorners(radius: 10.0)` on that art (`:857`) — a tenth of the side, not the chat
    /// list's quarter, because the tile is smaller.
    public static let miniPlayerArtRadius: CGFloat = 10
    /// `sideInset = 16.0` in the same layout (`:846`).
    public static let miniPlayerSideInset: CGFloat = 16
    /// Doni's own: the strip floats as a capsule in this build, so its content keeps 12 pt of glass
    /// on each side rather than the full-bleed panel's 16.
    public static let miniPlayerFloatInset: CGFloat = 12
    /// Doni's own: the strip is a way back to the player rather than the player, so the progress
    /// keeps the hairline weight the rest of the shell uses.
    public static let progressBarHeight: CGFloat = 2

    /// `buttonSize = CGSize(width: 64.0, height: 64.0)` for the transport row (`:887`); the glyph
    /// inside it is a 76 pt asset box (`:899`), which an SF Symbol cannot be sized from, so the
    /// point sizes live with the screen that draws them.
    public static let transportButton: CGFloat = 64

    /// `tabBarHeight = 49.0 + bottomInset` (`TabBarController.swift:206`), the band the list
    /// scrolls under. Doni's bar floats instead — see `TelegramFloatingBarMetrics` — so this is the
    /// height the *content* is inset by, not the height of anything drawn.
    public static let tabBarHeight: CGFloat = 49
    /// The item block inside that band, icon over label (`TabBarNode.swift:45`).
    public static let tabItemHeight: CGFloat = 45
    /// `horizontalSpacing = 4.0` — the only gap in the item (`:35`).
    public static let tabIconToLabel: CGFloat = 4
    /// Doni's own: the reference tints bundled PNGs whose box never appears in source, and an SF
    /// Symbol has to be given one. 24 keeps the glyph clear of the 45 pt block's label.
    public static let tabGlyphSide: CGFloat = 24

    /// Doni's own — the channel strip above the search pill, wearing the search bar's own fill.
    public static let chipHeight: CGFloat = 30
    public static let chipHorizontalPadding: CGFloat = 12
    public static let chipGap: CGFloat = 8
    public static let chipFont = Font.system(size: 14, weight: .semibold)
}

/// The bar on top of a screen: a floating glass pill, not the full-bleed band the photo shows.
///
/// The first build drew the photo's band literally and the user rejected it on the device, so the
/// band became a pill — rounded like the tab bar it faces — holding the photo's own contents: a
/// centred large title, a text action at the leading edge and icon actions at the trailing one.
/// What the photo measures is kept; what a floating pill needs that a band did not is Doni's own
/// and marked so. `Docs/design-tokens.md`, "The bar, as photographed".
public enum TelegramBarMetrics {
    /// The row of controls is 44 pt tall (`vedges 100`: 172 → 302 px) — the measured core the
    /// pill wraps.
    public static let contentHeight: CGFloat = 44
    /// Doni's own: 4 pt of glass above and below the controls, so the pill is 52 — the same
    /// proportions the photo's capsule keeps inside its band, on a vessel that floats.
    public static let padding: CGFloat = 4
    public static let height: CGFloat = contentHeight + 2 * padding

    /// Both edge actions end 16 pt from an edge (`hedges 225`: the group runs to 1122 px = 374 pt)
    /// — now the pill's own margin rather than the band's.
    public static let sideInset: CGFloat = 16
    /// Doni's own: the pill floats this far below the safe area, the same air the strip keeps
    /// above the tab bar.
    public static let topGap: CGFloat = 8
    /// Doni's own: the first row starts this far under the pill — the photo's 12.7, rounded.
    public static let belowGap: CGFloat = 12
    /// What a list insets its content by so it begins below the floating pill and scrolls under it.
    public static var topClearance: CGFloat { topGap + height + belowGap }

    /// The trailing actions sit on the photo's 38.9 pt pitch (`hedges 225`: 773 → 1123 px).
    public static let actionPitch: CGFloat = 38.9
    /// Doni's own: the reference's bar icons are PNG assets whose boxes never appear in source, so
    /// the glyph is sized to land on the photo's 19.3 pt of icon ink (`bands 780 1120 150 320`).
    public static let actionGlyph: CGFloat = 22
    /// Doni's own: how far the centred title keeps from the widest edge group. The first build
    /// padded by the photo's *three*-icon group whatever the screen actually had, and "Thư viện"
    /// drew as "Thứ v…" on the device.
    public static let titleGuard: CGFloat = 12
}

/// The tab screens' header, after the Apple Music set the user pointed at: the title set left in
/// `bold(34)` with round glass actions beside it and the list scrolling under the pair. Every
/// number here is Doni's own — the source the shell was measured against has no such header.
public enum TelegramHeaderMetrics {
    /// One line of `bold(34)`.
    public static let titleBox: CGFloat = 41
    /// Air between the safe area and the title, and under the header's one row.
    public static let topPadding: CGFloat = 6
    public static let bottomPadding: CGFloat = 8
    public static let sideInset: CGFloat = TelegramBarMetrics.sideInset
    /// The round glass actions the header carries, one per action.
    public static let actionCircle: CGFloat = 40
    public static let actionGlyph: CGFloat = 17
    public static let actionGap: CGFloat = 10
    /// What a list insets its content by to begin below the header and scroll under it.
    public static var topClearance: CGFloat { topPadding + titleBox + bottomPadding }
    /// The search field's own height — the header's second row.
    public static let fieldHeight: CGFloat = 40
    /// The search screen's header is the title plus a field row under it.
    public static var searchClearance: CGFloat { topClearance + actionGap + fieldHeight }
}

/// The tab bar the photo shows: nothing is full-bleed — the capsule and a separate search circle
/// float 20 pt clear of the screen's edges and the list scrolls under them.
/// `Docs/design-tokens.md`, "The floating tab bar, as photographed".
public enum TelegramFloatingBarMetrics {
    /// The gap from the left edge, the right edge and the *physical* bottom of the screen
    /// (`hedges 2380`: 60 px; `vedges 600`: the capsule ends at 2472 px = 824 pt of 844).
    public static let margin: CGFloat = 20
    /// Capsule top 2262 px, bottom 2472 px → 67.3 pt (`vedges 400`).
    public static let height: CGFloat = 67.3
    /// Three items in the photo's 278 pt capsule (`hedges 2380`: 60 → 894 px). Doni puts four in the
    /// same width, which is its own decision rather than a measurement.
    public static let itemPitch: CGFloat = 92.7
    /// The capsule itself: 278 pt, which is what is left between the two margins once the search
    /// circle and its gap have taken theirs (390 − 40 − 64 − 8).
    public static let capsuleWidth: CGFloat = 278
    /// Doni's own: four tabs in the photo's three-item capsule, so each item is a quarter of it.
    public static let itemWidth: CGFloat = capsuleWidth / 4
    /// Doni's own box for the glyph — the reference's tab icons are bundled PNGs — sized so the
    /// ink lands on the measured 19.3 pt.
    public static let iconBox: CGFloat = 24
    /// The box's top, so the glyph's centre is the measured 25.1 pt below the band's.
    public static let iconTop: CGFloat = iconCentre - iconBox / 2
    /// One line of `medium(10)`, which is what the label is drawn with.
    public static let labelBox: CGFloat = 12
    public static let labelTop: CGFloat = labelCentre - labelBox / 2
    /// Search is not a field in the bar: it is a 64 pt glass circle 8 pt after the capsule
    /// (`hedges 2380`: 918 → 1110 px; `vedges 1014`: 2280 → 2472 px).
    public static let searchCircle: CGFloat = 64
    public static let searchCircleGap: CGFloat = 8
    /// Doni's own: the point size that puts the loupe's ink on the 21.0 pt the circle measures
    /// (`bands 918 1110 2280 2472`: 2344 → 2406 px, centred in the circle).
    public static let searchGlyph: CGFloat = 24
    /// The item's two rows, measured from the band's top: icon ink centre 25.1 pt
    /// (`bands 300 480 2270 2472`: 2320 → 2371 px) and label ink centre 50.3 pt (2410 → 2435 px).
    public static let iconCentre: CGFloat = 25.1
    public static let labelCentre: CGFloat = 50.3

    /// Doni's own: the gap between the strip and the bar, both of which float, so the two
    /// capsules read as one stack rather than as two unrelated pills.
    public static let stripGap: CGFloat = 8

    /// How far a list has to run before its last row clears the floating chrome. The reference
    /// scrolls its list *under* the bar (`ChatListUI` insets the collection, it does not shrink
    /// it), so this is content margin rather than a layout row.
    public static func clearance(stripVisible: Bool) -> CGFloat {
        margin + height + (stripVisible ? TelegramShellMetrics.miniPlayerHeight + stripGap : 0)
    }
}

/// The music bar's fonts, taken from the calls that set them in
/// `OverlayAudioPlayerControlsNode.swift`.
public enum TelegramShellTypography {
    /// `titleFont = Font.semibold(17.0)` (`:111`).
    public static let title = Font.system(size: 17, weight: .semibold)
    /// `descriptionFont = Font.regular(15.0)` (`:112`).
    public static let artist = Font.system(size: 15, weight: .regular)
    /// `Font.medium(12.0)` on both timestamp labels (`:267`, `:270`).
    public static let timestamp = Font.system(size: 12, weight: .medium)
    /// `Font.medium(10.0)` under an icon (`TabBarNode.swift:20`).
    public static let tabLabel = Font.system(size: 10, weight: .medium)
    /// The photo's bar title is a *large* centred title, not the source's literal `semibold(17)`
    /// (`DocumentPreviewController.swift:202`): its ink spans 16.0 pt (`bands 380 800 150 341`) and
    /// its stems measure 7 px where the row's `semibold(13)` measures 4, i.e. 13 × 7 ÷ 4 ≈ 22 pt at
    /// the same weight.
    public static let barLargeTitle = Font.system(size: 22, weight: .semibold)
    /// Doni's own: on a floating pill the leading word is an iOS bar button, which is `regular(17)`
    /// — the measured `semibold(14)` belonged to the band's capsule and went with it.
    public static let barAction = Font.system(size: 17, weight: .regular)
    /// Doni's own: the tab screens' large title, `bold(34)` after the Apple Music set the user
    /// pointed at.
    public static let largeTitle = Font.system(size: 34, weight: .bold)
    /// Doni's own: the expanded player's words, after the same set — `bold(22)` over `regular(18)`.
    public static let playingTitle = Font.system(size: 22, weight: .bold)
    public static let playingArtist = Font.system(size: 18, weight: .regular)
}

/// Motion lifted from `ChatListBadgeNode.swift` — the bubble Telegram animates into the
/// unread-bubble slot this app reuses for a track's download state.
public enum TelegramShellMotion {
    /// `:205` alpha 0 → 1 and `:206` the position easing in, both 0.15 s.
    public static let appear = Animation.easeInOut(duration: 0.15)
    /// `:161` alpha 1 → 0, 0.15 s.
    public static let disappear = Animation.easeInOut(duration: 0.15)
    /// `:170` scale 1.0 → 0.0001, 0.12 s.
    public static let collapse = Animation.easeInOut(duration: 0.12)
    /// `:128`/`:134` entrance scale 0.0001 → 1.2, 0.2 s — the overshoot Telegram lets a bubble
    /// land with before it settles at 1.
    public static let pop = Animation.easeOut(duration: 0.2)
    /// `:206` — a bubble enters from 8 pt above where it rests.
    public static let slideIn: CGFloat = 8
    /// An artwork image replacing a placeholder: the same 0.15 s alpha the bubble fades with.
    public static let crossfade = Animation.easeInOut(duration: 0.15)
}
