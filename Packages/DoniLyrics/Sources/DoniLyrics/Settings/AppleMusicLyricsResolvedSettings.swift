#if os(iOS)
import Foundation

@MainActor
extension AppSettings {
    public var appleMusicLyricsMotionProfile:
        AppleMusicLyricsMotionProfile? {
        appleMusicLyrics.usesAppleMusic26Motion
            ? .iOS26_6
            : nil
    }

    public var appleMusicLyricsTypographyProfile:
        AppleMusicLyricsTypographyProfile? {
        appleMusicLyrics.usesAppleMusic26Motion
            ? .iOS26_6
            : nil
    }

    public var effectiveAppleMusicLyricsPrimaryFontSize: Double {
        appleMusicLyricsTypographyProfile?.primaryFontSize
            ?? lyricsFontSize
    }

    public var effectiveAppleMusicLyricsLineSpacing: Double {
        appleMusicLyricsMotionProfile?.lineSpacing
            ?? lyricsLineSpacing
    }

    public var effectiveAppleMusicLyricsCurrentLineScale: Double {
        guard let profile = appleMusicLyricsMotionProfile else {
            return lyricsCurrentLineScale
        }
        // Apple's selected line stays at identity. The profile's 0.98 value
        // belongs to deselected lines and is applied by the row renderer.
        _ = profile
        return 1
    }

    public var effectiveAppleMusicLyricsCascadeDelay: TimeInterval {
        appleMusicLyricsMotionProfile?.cascadeDelay
            ?? lyricsFocusCascadeDelay
    }

    public var effectiveAppleMusicLyricsCascadeDelayIncrease:
        TimeInterval {
        appleMusicLyricsMotionProfile == nil
            ? lyricsFocusCascadeDelayIncrease
            : 0
    }

    public var effectiveAppleMusicLyricsFollowingDelay: TimeInterval {
        appleMusicLyricsMotionProfile == nil
            ? lyricsFocusCascadeFollowingDelay
            : 0
    }

    public var effectiveAppleMusicLyricsCatchUpRatio: Double {
        appleMusicLyricsMotionProfile == nil
            ? lyricsFocusCascadeCatchUpRatio
            : 1
    }

    public var effectiveAppleMusicLyricsChaseSpeedGradient: Double {
        appleMusicLyricsMotionProfile == nil
            ? lyricsFocusCascadeChaseSpeedGradient
            : 1
    }

    public var effectiveAppleMusicLyricsCascadeDuration: TimeInterval {
        appleMusicLyricsMotionProfile == nil
            ? lyricsFocusCascadeDuration
            : 0
    }

    public var effectiveAppleMusicLyricsSnapThreshold: TimeInterval {
        appleMusicLyricsMotionProfile == nil
            ? lyricsFocusSnapThreshold
            : 0
    }

    public var effectiveAppleMusicLyricsFocusColorLeadTime: TimeInterval {
        appleMusicLyricsMotionProfile == nil
            ? lyricsFocusColorLeadTime
            : 0
    }
}
#endif
