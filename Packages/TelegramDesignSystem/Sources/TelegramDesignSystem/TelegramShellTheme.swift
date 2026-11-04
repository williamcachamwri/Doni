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
/// pick a channel. The strip and the tab bar now wear the numbers of the Apple Music kit the user
/// pointed at (`AMToolbarView.swift`, `AMTabBarController.swift`); the chips stay Telegram's.
public enum TelegramShellMetrics {
    /// The toolbar is a 40 pt artwork inset 8 into its 56 pt bar (`AMToolbarView.swift:109-114`).
    public static let miniPlayerHeight: CGFloat = 56
    public static let miniPlayerArt: CGFloat = 40
    /// `imageView.layer.cornerRadius = 6` (`AMToolbarView.swift:101`).
    public static let miniPlayerArtRadius: CGFloat = 6

    /// `buttonSize = CGSize(width: 64.0, height: 64.0)` for the transport row (`:887`); the glyph
    /// inside it is a 76 pt asset box (`:899`), which an SF Symbol cannot be sized from, so the
    /// point sizes live with the screen that draws them.
    public static let transportButton: CGFloat = 64

    /// The standard tab bar's own band (`TabBarController.swift:206` measured it at 49 + inset;
    /// the kit's is the same UITabBar). The kit's items are the system's: an icon over a label.
    public static let tabBarHeight: CGFloat = 49

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

/// The bottom chrome after the Apple Music kit: a full-width toolbar 6 pt above the standard tab
/// bar, both sitting on one backdrop that runs from the toolbar's top to the screen's bottom — no
/// capsule, no separate search circle. `AMTabBarController.swift`, `AMToolbarView.swift`.
public enum TelegramFloatingBarMetrics {
    /// `toolbarView` insets 12 pt from each edge (`AMTabBarController.swift:48-49`).
    public static let toolbarMargin: CGFloat = 12
    /// `toolbarView.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -6)` (`:50`).
    public static let toolbarToTabBar: CGFloat = 6

    /// How far a list has to run before its last row clears the chrome. The kit scrolls its lists
    /// *under* the toolbar and tab bar — the backdrop blurs them as they pass — so this is content
    /// margin rather than a layout row.
    public static func clearance(stripVisible: Bool) -> CGFloat {
        TelegramShellMetrics.tabBarHeight
            + (stripVisible ? TelegramShellMetrics.miniPlayerHeight + toolbarToTabBar : 0)
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
