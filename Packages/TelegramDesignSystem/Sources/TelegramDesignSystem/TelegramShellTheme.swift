import SwiftUI

/// The shell's numbers that are not the music screens'. On iOS 26 the system's `TabView` accessory,
/// navigation bar and scroll insets do the floating-bar chrome, so only what Doni still measures
/// itself is left here.
public enum TelegramShellMetrics {
    /// `buttonSize = CGSize(width: 64.0, height: 64.0)` for the transport row
    /// (`OverlayAudioPlayerControlsNode.swift:887`).
    public static let transportButton: CGFloat = 64
}

/// The player bar's fonts, from the calls that set them in `OverlayAudioPlayerControlsNode.swift`.
public enum TelegramShellTypography {
    /// `Font.medium(12.0)` on both timestamp labels (`:267`, `:270`).
    public static let timestamp = Font.system(size: 12, weight: .medium)
}

/// Motion lifted from `ChatListBadgeNode.swift` — the bubble Telegram animates into the unread-bubble
/// slot this app reuses for a track's download state.
public enum TelegramShellMotion {
    /// `:205` alpha 0 → 1 and `:206` the position easing in, both 0.15 s.
    public static let appear = Animation.easeInOut(duration: 0.15)
    /// `:161` alpha 1 → 0, 0.15 s.
    public static let disappear = Animation.easeInOut(duration: 0.15)
    /// `:170` scale 1.0 → 0.0001, 0.12 s.
    public static let collapse = Animation.easeInOut(duration: 0.12)
    /// `:128`/`:134` entrance scale 0.0001 → 1.2, 0.2 s — the overshoot a bubble lands with before it settles at 1.
    public static let pop = Animation.easeOut(duration: 0.2)
    /// `:206` — a bubble enters from 8 pt above where it rests.
    public static let slideIn: CGFloat = 8
    /// An artwork image replacing a placeholder: the same 0.15 s alpha the bubble fades with.
    public static let crossfade = Animation.easeInOut(duration: 0.15)
}
