import SwiftUI

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
    /// Doni's own: the strip is a way back to the player rather than the player, so the progress
    /// keeps the hairline weight the rest of the shell uses.
    public static let progressBarHeight: CGFloat = 2

    /// `scrubberThickness = 7.0` in the expanded panel's own scrubber (`:266`), drawn with round
    /// caps and no handle (`:716`).
    public static let scrubberHeight: CGFloat = 7
    /// `buttonSize = CGSize(width: 64.0, height: 64.0)` for the transport row (`:887`); the glyph
    /// inside it is a 76 pt asset box (`:899`), which an SF Symbol cannot be sized from, so the
    /// point sizes live with the screen that draws them.
    public static let transportButton: CGFloat = 64
    /// `height: 10.0 + 8.0 * 2.0` — the band the 7 pt line is drawn in, so a finger has 26 pt to
    /// land on rather than 7 (`:867`).
    public static let scrubberBand: CGFloat = 26
    /// `buttonsWidth = min(width − insets − 2 × (sideInset + 60.0), 320.0)` (`:888`): the three
    /// centre buttons share a band that stops at 320 however wide the phone is.
    public static let transportCentreBand: CGFloat = 320
    /// The two side buttons are 64 pt boxes starting 12 pt outside the bar's own 16 pt inset
    /// (`x = leftInset + sideInset − 12.0`, mirrored at `:891` and `:892`), so the glyphs keep the
    /// column the rest of the panel uses while the touch boxes overhang it.
    public static let transportSlotInset: CGFloat = miniPlayerSideInset - 12
    /// Doni's own: the line under the transport that says what the loop is currently holding —
    /// one `medium(12)` row (`:267`) with room for the button beside it.
    public static let sliceCaptionHeight: CGFloat = 20

    /// `tabBarHeight = 49.0 + bottomInset` (`TabBarController.swift:206`), the band the list
    /// scrolls under.
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
