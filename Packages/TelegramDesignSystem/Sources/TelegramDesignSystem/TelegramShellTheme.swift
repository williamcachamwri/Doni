import SwiftUI

/// The parts of the shell Telegram does not draw: Doni's own mini player and channel chips, and
/// the motion everything borrowed from `ChatListBadgeNode.swift`.
///
/// Two of the three numbers below are Doni's, measured off the design lab rather than off the
/// reference, and are marked as such. The motion is not: it is the badge's own timing, which is
/// the closest thing in the reference to a state bubble appearing and going away.
public enum TelegramShellMetrics {
    /// Doni's own — Telegram has no mini player outside a chat. A row is 68 and a cover tile is
    /// 54, so the strip clears one row's worth of artwork without competing with the list.
    public static let miniPlayerHeight: CGFloat = 64
    /// The 54 pt tile inside it, the same side the list's icon column uses.
    public static let miniPlayerArt: CGFloat = 40
    public static let progressBarHeight: CGFloat = 2

    /// Doni's own — the channel strip above the search pill, wearing the search bar's own fill.
    public static let chipHeight: CGFloat = 30
    public static let chipHorizontalPadding: CGFloat = 12
    public static let chipGap: CGFloat = 8
    public static let chipFont = Font.system(size: 14, weight: .semibold)
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
