import Foundation
import Observation

/// The lyrics half of the reference's settings object, lifted out with its defaults,
/// its UserDefaults keys and its clamps intact. Each of those numbers is what the copied
/// renderer reads to decide how big, how bright and how fast a line is, so they are the
/// reference's numbers rather than approximations of them.
@MainActor
@Observable
public final class AppSettings {
    private enum Key {
            static let appleMusicLyricsInterfaceAutoHideDelay =
                "appleMusicLyricsInterfaceAutoHideDelay"
            static let appleMusicLyricsScrollHideThreshold =
                "appleMusicLyricsScrollHideThreshold"
            static let lyricsFontSize = "lyricsFontSize"
            static let lyricsFontWeight = "lyricsFontWeight"
            static let lyricsCurrentLineScale = "lyricsCurrentLineScale"
            static let lyricsLineSpacing = "lyricsLineSpacing"
            static let lyricsBlurIntensity = "lyricsBlurIntensity"
            static let lyricsUsesUniformDimmingWhileBrowsing =
                "lyricsUsesUniformDimmingWhileBrowsing"
            static let lyricsDistanceBlurScale = "lyricsDistanceBlurScale"
            static let lyricsHiddenInterfaceBlurScale = "lyricsHiddenInterfaceBlurScale"
            static let lyricsDimAmount = "lyricsDimAmount"
            static let lyricsTapToSeek = "lyricsTapToSeek"
            static let lyricsLongPressToShare = "lyricsLongPressToShare"
            static let lyricsWordByWord = "lyricsWordByWord"
            static let lyricsPseudoWordByWord = "lyricsPseudoWordByWord"
            static let lyricsDuetLayoutEnabled = "lyricsDuetLayoutEnabled"
            static let lyricsLiftMode = "lyricsLiftMode"
            static let lyricsHighlightGradientWidth =
                "lyricsHighlightGradientWidth"
            static let lyricsHighlightGradientReduction =
                "lyricsHighlightGradientReduction"
            static let lyricsGlowEnabled = "lyricsGlowEnabled"
            static let lyricsInterludeCountdownEnabled = "lyricsInterludeCountdownEnabled"
            static let lyricsRefreshRate = "lyricsRefreshRate"
            static let lyricsLongSyllableDetectionMode =
                "lyricsLongSyllableDetectionMode"
            static let lyricsGlowLongSyllablesOnly =
                "lyricsGlowLongSyllablesOnly"
            static let lyricsLongSyllableDurationThreshold =
                "lyricsLongSyllableDurationThreshold"
            static let lyricsLongToneExpansionAmount =
                "lyricsLongToneExpansionAmount"
            static let lyricsGlowIntensity = "lyricsGlowIntensity"
            static let lyricsRomanizationEnabled = "lyricsRomanizationEnabled"
            static let lyricsRomanizationFontScale =
                "lyricsRomanizationFontScale"
            static let lyricsRomanizationOpacity =
                "lyricsRomanizationOpacity"
            static let lyricsRomanizationDisplayMode =
                "lyricsRomanizationDisplayMode"
            static let lyricsTranslationEnabled = "lyricsTranslationEnabled"
            static let lyricsTranslationDisplayMode = "lyricsTranslationDisplayMode"
            static let lyricsTranslationFontScale = "lyricsTranslationFontScale"
            static let lyricsTranslationOpacity = "lyricsTranslationOpacity"
            static let lyricsAutoFollow = "lyricsAutoFollow"
            static let lyricsFollowDelay = "lyricsFollowDelay"
            static let lyricsFocusPosition = "lyricsFocusPosition"
            static let lyricsFocusCascadeDelay = "lyricsFocusCascadeDelay"
            static let lyricsFocusCascadeDelayIncrease =
                "lyricsFocusCascadeDelayIncrease"
            static let lyricsFocusCascadeFollowingDelay =
                "lyricsFocusCascadeFollowingDelay"
            static let lyricsFocusCascadeCatchUpRatio =
                "lyricsFocusCascadeCatchUpRatio"
            static let lyricsFocusCascadeChaseSpeedGradient =
                "lyricsFocusCascadeChaseSpeedGradient"
            static let lyricsFocusCascadeDuration = "lyricsFocusCascadeDuration"
            static let lyricsFocusSnapThreshold = "lyricsFocusSnapThreshold"
            static let lyricsFocusCascadeBounceEnabled = "lyricsFocusCascadeBounceEnabled"
            static let lyricsFocusCascadeBounce = "lyricsFocusCascadeBounce"
            static let lyricsFocusCascadeBounceGradient =
                "lyricsFocusCascadeBounceGradient"
            static let lyricsFocusScaleBounceEnabled = "lyricsFocusScaleBounceEnabled"
            static let lyricsFocusScaleBounce = "lyricsFocusScaleBounce"
            static let lyricsFocusScaleBounceDuration =
                "lyricsFocusScaleBounceDuration"
            static let legacyLyricsFocusCascadeMinimumBounceDuration =
                "lyricsFocusCascadeMinimumBounceDuration"
            static let lyricsFocusColorLeadTime = "lyricsFocusColorLeadTime"
            static let lyricsAdvanceTime = "lyricsAdvanceTime"
            static let lyricsAdvanceTimeAppliesToWordByWord =
                "lyricsAdvanceTimeAppliesToWordByWord"
            static let legacyLyricsKeepsScreenAwake = "lyricsKeepsScreenAwake"
    }

    public static let defaultAppleMusicLyricsInterfaceAutoHideDelay = 5.0

    public static let appleMusicLyricsInterfaceAutoHideDelayRange = 3.0...15.0

    public static let defaultAppleMusicLyricsScrollHideThreshold = 200.0

    public static let appleMusicLyricsScrollHideThresholdRange = 40.0...240.0

    public static let defaultLyricsFontSize = 34.0

    public static let defaultLyricsFontWeight: LyricsFontWeight = .heavy

    public static let defaultLyricsCurrentLineScale = 1.02

    public static let defaultLyricsLineSpacing = 28.0

    public static let defaultLyricsBlurIntensity = 0.8

    public static let defaultLyricsUsesUniformDimmingWhileBrowsing = true

    public static let defaultLyricsDimAmount = 1.0

    public static let defaultLyricsFocusPosition = 0.25

    public static let lyricsFocusPositionRange = 0.05...0.8

    public static let lyricsCurrentLineScaleRange = 1.0...1.5

    public static let defaultLyricsDistanceBlurScale = 1.05

    public static let defaultLyricsHiddenInterfaceBlurScale = 0.85

    public static let lyricsDistanceBlurScaleRange = 0.0...1.5

    public static let defaultLyricsFocusCascadeDelay = 0.021

    public static let lyricsFocusCascadeDelayRange = 0.0...0.1

    public static let defaultLyricsFocusCascadeDelayIncrease = 0.005

    public static let lyricsFocusCascadeDelayIncreaseRange = 0.0...0.1

    public static let defaultLyricsFocusCascadeFollowingDelay = 0.030

    public static let lyricsFocusCascadeFollowingDelayRange = 0.0...0.2

    public static let defaultLyricsFocusCascadeCatchUpRatio = 0.97

    public static let lyricsFocusCascadeCatchUpRatioRange = 0.5...1.0

    public static let defaultLyricsFocusCascadeChaseSpeedGradient = 0.70

    public static let lyricsFocusCascadeChaseSpeedGradientRange = 0.0...1.0

    public static let defaultLyricsFocusCascadeDuration = 0.74

    public static let lyricsFocusCascadeDurationRange = 0.2...1.2

    public static let defaultLyricsFocusSnapThreshold = 0.26

    public static let lyricsFocusSnapThresholdRange = 0.05...0.5

    public static let defaultLyricsFocusCascadeBounceEnabled = true

    public static let defaultLyricsFocusCascadeBounce = 0.26

    public static let lyricsFocusCascadeBounceRange = 0.0...0.8

    public static let defaultLyricsFocusCascadeBounceGradient = 0.85

    public static let lyricsFocusCascadeBounceGradientRange = 0.0...1.0

    public static let defaultLyricsFocusScaleBounceEnabled = true

    public static let defaultLyricsFocusScaleBounce = 0.32

    public static let lyricsFocusScaleBounceRange = 0.0...0.5

    public static let defaultLyricsFocusScaleBounceDuration = 0.58

    public static let lyricsFocusScaleBounceDurationRange = 0.15...0.8

    public static let defaultLyricsFocusColorLeadTime = 0.0

    public static let lyricsFocusColorLeadTimeRange = -0.3...0.3

    public static let defaultLyricsRomanizationFontScale = 0.65

    public static let defaultLyricsRomanizationOpacity = 0.9

    public static let defaultLyricsTranslationFontScale = 0.65

    public static let defaultLyricsTranslationOpacity = 0.9

    public static let defaultLyricsLiftMode: LyricsLiftMode = .character

    public static let defaultLyricsLongSyllableDetectionMode:
        LyricsLongSyllableDetectionMode = .character

    public static let defaultLyricsGlowLongSyllablesOnly = true

    public static let defaultLyricsLongSyllableDurationThreshold = 0.95

    public static let lyricsLongSyllableDurationThresholdRange = 0.3...1.5

    public static let defaultLyricsLongToneExpansionAmount = 0.05

    public static let lyricsLongToneExpansionAmountRange = 0.0...0.15

    public static let defaultLyricsHighlightGradientWidth = 0.7

    public static let lyricsHighlightGradientWidthRange = 0.4...3.0

    public static let defaultLyricsHighlightGradientReduction = 0.65

    public static let lyricsHighlightGradientReductionRange = 0.0...1.0

    public var appleMusicLyricsInterfaceAutoHideDelay: Double {
        didSet {
            defaults.set(
                appleMusicLyricsInterfaceAutoHideDelay,
                forKey: Key.appleMusicLyricsInterfaceAutoHideDelay
            )
        }
    }

    public var appleMusicLyricsScrollHideThreshold: Double {
        didSet {
            defaults.set(
                appleMusicLyricsScrollHideThreshold,
                forKey: Key.appleMusicLyricsScrollHideThreshold
            )
        }
    }

    public var lyricsFontSize: Double {
        didSet { defaults.set(lyricsFontSize, forKey: Key.lyricsFontSize) }
    }

    public var lyricsFontWeight: LyricsFontWeight {
        didSet {
            defaults.set(
                lyricsFontWeight.rawValue,
                forKey: Key.lyricsFontWeight
            )
        }
    }

    public var lyricsCurrentLineScale: Double {
        didSet { defaults.set(lyricsCurrentLineScale, forKey: Key.lyricsCurrentLineScale) }
    }

    public var lyricsLineSpacing: Double {
        didSet { defaults.set(lyricsLineSpacing, forKey: Key.lyricsLineSpacing) }
    }

    public var lyricsBlurIntensity: Double {
        didSet { defaults.set(lyricsBlurIntensity, forKey: Key.lyricsBlurIntensity) }
    }

    public var lyricsUsesUniformDimmingWhileBrowsing: Bool {
        didSet {
            defaults.set(
                lyricsUsesUniformDimmingWhileBrowsing,
                forKey: Key.lyricsUsesUniformDimmingWhileBrowsing
            )
        }
    }

    public var lyricsDistanceBlurScale: Double {
        didSet {
            defaults.set(
                lyricsDistanceBlurScale,
                forKey: Key.lyricsDistanceBlurScale
            )
        }
    }

    public var lyricsHiddenInterfaceBlurScale: Double {
        didSet {
            defaults.set(
                lyricsHiddenInterfaceBlurScale,
                forKey: Key.lyricsHiddenInterfaceBlurScale
            )
        }
    }

    public var lyricsDimAmount: Double {
        didSet { defaults.set(lyricsDimAmount, forKey: Key.lyricsDimAmount) }
    }

    public var lyricsTapToSeek: Bool {
        didSet { defaults.set(lyricsTapToSeek, forKey: Key.lyricsTapToSeek) }
    }

    public var lyricsLongPressToShare: Bool {
        didSet {
            defaults.set(
                lyricsLongPressToShare,
                forKey: Key.lyricsLongPressToShare
            )
        }
    }

    public var lyricsWordByWord: Bool {
        didSet { defaults.set(lyricsWordByWord, forKey: Key.lyricsWordByWord) }
    }

    public var lyricsPseudoWordByWord: Bool {
        didSet { defaults.set(lyricsPseudoWordByWord, forKey: Key.lyricsPseudoWordByWord) }
    }

    public var lyricsDuetLayoutEnabled: Bool {
        didSet {
            defaults.set(
                lyricsDuetLayoutEnabled,
                forKey: Key.lyricsDuetLayoutEnabled
            )
        }
    }

    public var lyricsLiftMode: LyricsLiftMode {
        didSet {
            defaults.set(
                lyricsLiftMode.rawValue,
                forKey: Key.lyricsLiftMode
            )
        }
    }

    public var lyricsHighlightGradientWidth: Double {
        didSet {
            defaults.set(
                lyricsHighlightGradientWidth,
                forKey: Key.lyricsHighlightGradientWidth
            )
        }
    }

    public var lyricsHighlightGradientReduction: Double {
        didSet {
            defaults.set(
                lyricsHighlightGradientReduction,
                forKey: Key.lyricsHighlightGradientReduction
            )
        }
    }

    /// The frame rate the lyrics column drives its per-line timelines at. The desktop column reads it
    /// straight off `EnvironmentValues.effectiveLyricsRefreshRate`; the phone has never asked.
    public var lyricsRefreshRate: LyricsRefreshRate {
        didSet { defaults.set(lyricsRefreshRate.rawValue, forKey: Key.lyricsRefreshRate) }
    }

    /// Whether Music counts down the gap between lines with its three dots. The desktop column
    /// pauses that on request; the phone has never asked, so it keeps the reference default of on.
    public var lyricsInterludeCountdownEnabled: Bool {
        didSet { defaults.set(lyricsInterludeCountdownEnabled, forKey: Key.lyricsInterludeCountdownEnabled) }
    }

    public var lyricsGlowEnabled: Bool {
        didSet { defaults.set(lyricsGlowEnabled, forKey: Key.lyricsGlowEnabled) }
    }

    public var lyricsLongSyllableDetectionMode:
        LyricsLongSyllableDetectionMode {
        didSet {
            defaults.set(
                lyricsLongSyllableDetectionMode.rawValue,
                forKey: Key.lyricsLongSyllableDetectionMode
            )
        }
    }

    public var lyricsGlowLongSyllablesOnly: Bool {
        didSet {
            defaults.set(
                lyricsGlowLongSyllablesOnly,
                forKey: Key.lyricsGlowLongSyllablesOnly
            )
        }
    }

    public var lyricsLongSyllableDurationThreshold: Double {
        didSet {
            defaults.set(
                lyricsLongSyllableDurationThreshold,
                forKey: Key.lyricsLongSyllableDurationThreshold
            )
        }
    }

    public var lyricsLongToneExpansionAmount: Double {
        didSet {
            defaults.set(
                lyricsLongToneExpansionAmount,
                forKey: Key.lyricsLongToneExpansionAmount
            )
        }
    }

    public var lyricsGlowIntensity: Double {
        didSet { defaults.set(lyricsGlowIntensity, forKey: Key.lyricsGlowIntensity) }
    }

    public var lyricsRomanizationEnabled: Bool {
        didSet {
            defaults.set(
                lyricsRomanizationEnabled,
                forKey: Key.lyricsRomanizationEnabled
            )
        }
    }

    public var lyricsRomanizationFontScale: Double {
        didSet {
            defaults.set(
                lyricsRomanizationFontScale,
                forKey: Key.lyricsRomanizationFontScale
            )
        }
    }

    public var lyricsRomanizationOpacity: Double {
        didSet {
            defaults.set(
                lyricsRomanizationOpacity,
                forKey: Key.lyricsRomanizationOpacity
            )
        }
    }

    public var lyricsRomanizationDisplayMode: LyricsTranslationDisplayMode {
        didSet {
            defaults.set(
                lyricsRomanizationDisplayMode.rawValue,
                forKey: Key.lyricsRomanizationDisplayMode
            )
        }
    }

    public var lyricsTranslationEnabled: Bool {
        didSet { defaults.set(lyricsTranslationEnabled, forKey: Key.lyricsTranslationEnabled) }
    }

    public var lyricsTranslationDisplayMode: LyricsTranslationDisplayMode {
        didSet {
            defaults.set(
                lyricsTranslationDisplayMode.rawValue,
                forKey: Key.lyricsTranslationDisplayMode
            )
        }
    }

    public var lyricsTranslationFontScale: Double {
        didSet { defaults.set(lyricsTranslationFontScale, forKey: Key.lyricsTranslationFontScale) }
    }

    public var lyricsTranslationOpacity: Double {
        didSet { defaults.set(lyricsTranslationOpacity, forKey: Key.lyricsTranslationOpacity) }
    }

    public var lyricsAutoFollow: Bool {
        didSet { defaults.set(lyricsAutoFollow, forKey: Key.lyricsAutoFollow) }
    }

    public var lyricsFollowDelay: Double {
        didSet { defaults.set(lyricsFollowDelay, forKey: Key.lyricsFollowDelay) }
    }

    public var lyricsFocusPosition: Double {
        didSet { defaults.set(lyricsFocusPosition, forKey: Key.lyricsFocusPosition) }
    }

    public var lyricsFocusCascadeDelay: Double {
        didSet {
            defaults.set(
                lyricsFocusCascadeDelay,
                forKey: Key.lyricsFocusCascadeDelay
            )
        }
    }

    public var lyricsFocusCascadeDelayIncrease: Double {
        didSet {
            defaults.set(
                lyricsFocusCascadeDelayIncrease,
                forKey: Key.lyricsFocusCascadeDelayIncrease
            )
        }
    }

    public var lyricsFocusCascadeFollowingDelay: Double {
        didSet {
            defaults.set(
                lyricsFocusCascadeFollowingDelay,
                forKey: Key.lyricsFocusCascadeFollowingDelay
            )
        }
    }

    public var lyricsFocusCascadeCatchUpRatio: Double {
        didSet {
            defaults.set(
                lyricsFocusCascadeCatchUpRatio,
                forKey: Key.lyricsFocusCascadeCatchUpRatio
            )
        }
    }

    public var lyricsFocusCascadeChaseSpeedGradient: Double {
        didSet {
            defaults.set(
                lyricsFocusCascadeChaseSpeedGradient,
                forKey: Key.lyricsFocusCascadeChaseSpeedGradient
            )
        }
    }

    public var lyricsFocusCascadeBounceEnabled: Bool {
        didSet {
            defaults.set(
                lyricsFocusCascadeBounceEnabled,
                forKey: Key.lyricsFocusCascadeBounceEnabled
            )
        }
    }

    public var lyricsFocusCascadeBounce: Double {
        didSet {
            defaults.set(
                lyricsFocusCascadeBounce,
                forKey: Key.lyricsFocusCascadeBounce
            )
        }
    }

    public var lyricsFocusCascadeBounceGradient: Double {
        didSet {
            defaults.set(
                lyricsFocusCascadeBounceGradient,
                forKey: Key.lyricsFocusCascadeBounceGradient
            )
        }
    }

    public var lyricsFocusScaleBounceEnabled: Bool {
        didSet {
            defaults.set(
                lyricsFocusScaleBounceEnabled,
                forKey: Key.lyricsFocusScaleBounceEnabled
            )
        }
    }

    public var lyricsFocusScaleBounce: Double {
        didSet {
            defaults.set(
                lyricsFocusScaleBounce,
                forKey: Key.lyricsFocusScaleBounce
            )
        }
    }

    public var lyricsFocusScaleBounceDuration: Double {
        didSet {
            defaults.set(
                lyricsFocusScaleBounceDuration,
                forKey: Key.lyricsFocusScaleBounceDuration
            )
        }
    }

    public var lyricsFocusCascadeDuration: Double {
        didSet {
            defaults.set(
                lyricsFocusCascadeDuration,
                forKey: Key.lyricsFocusCascadeDuration
            )
        }
    }

    public var lyricsFocusSnapThreshold: Double {
        didSet {
            defaults.set(
                lyricsFocusSnapThreshold,
                forKey: Key.lyricsFocusSnapThreshold
            )
        }
    }

    public var lyricsFocusColorLeadTime: Double {
        didSet {
            defaults.set(
                lyricsFocusColorLeadTime,
                forKey: Key.lyricsFocusColorLeadTime
            )
        }
    }

    public var lyricsAdvanceTime: Double {
        didSet { defaults.set(lyricsAdvanceTime, forKey: Key.lyricsAdvanceTime) }
    }

    public var lyricsAdvanceTimeAppliesToWordByWord: Bool {
        didSet {
            defaults.set(
                lyricsAdvanceTimeAppliesToWordByWord,
                forKey: Key.lyricsAdvanceTimeAppliesToWordByWord
            )
        }
    }

    public var wordByWordLyricsAdvanceTime: TimeInterval {
        lyricsAdvanceTimeAppliesToWordByWord
            ? lyricsAdvanceTime
            : 0
    }

    public func effectiveLyricsAdvanceTime(
        hasSyllableSyncedLyrics: Bool
    ) -> TimeInterval {
        let usesWordByWordPresentation = hasSyllableSyncedLyrics
            ? lyricsWordByWord
            : lyricsPseudoWordByWord
        return usesWordByWordPresentation
            ? wordByWordLyricsAdvanceTime
            : lyricsAdvanceTime
    }

    public func effectiveLyricsAdvanceTime(
        for lyrics: [LyricLine]
    ) -> TimeInterval {
        effectiveLyricsAdvanceTime(
            hasSyllableSyncedLyrics:
                lyrics.contains(where: \.isSyllableSynced)
        )
    }

    private let defaults: UserDefaults
    public let appleMusicLyrics: AppleMusicLyricsPreferences
    public let lyricsInterlude: LyricsInterludePreferences

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appleMusicLyrics = AppleMusicLyricsPreferences(defaults: defaults)
        lyricsInterlude = LyricsInterludePreferences(defaults: defaults)
        let storedAppleMusicInterfaceAutoHideDelay = defaults.object(
            forKey: Key.appleMusicLyricsInterfaceAutoHideDelay
        ) as? Double ?? Self.defaultAppleMusicLyricsInterfaceAutoHideDelay
        appleMusicLyricsInterfaceAutoHideDelay = min(
            max(
                storedAppleMusicInterfaceAutoHideDelay,
                Self.appleMusicLyricsInterfaceAutoHideDelayRange.lowerBound
            ),
            Self.appleMusicLyricsInterfaceAutoHideDelayRange.upperBound
        )
        let storedAppleMusicScrollHideThreshold = defaults.object(
            forKey: Key.appleMusicLyricsScrollHideThreshold
        ) as? Double ?? Self.defaultAppleMusicLyricsScrollHideThreshold
        appleMusicLyricsScrollHideThreshold = min(
            max(
                storedAppleMusicScrollHideThreshold,
                Self.appleMusicLyricsScrollHideThresholdRange.lowerBound
            ),
            Self.appleMusicLyricsScrollHideThresholdRange.upperBound
        )
        lyricsFontSize = defaults.object(
            forKey: Key.lyricsFontSize
        ) as? Double ?? Self.defaultLyricsFontSize
        lyricsFontWeight = LyricsFontWeight(
            rawValue: defaults.string(forKey: Key.lyricsFontWeight) ?? ""
        ) ?? Self.defaultLyricsFontWeight
        let storedLyricsCurrentLineScale = defaults.object(
            forKey: Key.lyricsCurrentLineScale
        ) as? Double ?? Self.defaultLyricsCurrentLineScale
        lyricsCurrentLineScale = min(
            max(
                storedLyricsCurrentLineScale,
                Self.lyricsCurrentLineScaleRange.lowerBound
            ),
            Self.lyricsCurrentLineScaleRange.upperBound
        )
        lyricsLineSpacing = defaults.object(
            forKey: Key.lyricsLineSpacing
        ) as? Double ?? Self.defaultLyricsLineSpacing
        lyricsBlurIntensity = defaults.object(forKey: Key.lyricsBlurIntensity) as? Double
            ?? Self.defaultLyricsBlurIntensity
        lyricsUsesUniformDimmingWhileBrowsing = defaults.object(
            forKey: Key.lyricsUsesUniformDimmingWhileBrowsing
        ) as? Bool ?? Self.defaultLyricsUsesUniformDimmingWhileBrowsing
        let storedLyricsDistanceBlurScale = defaults.object(
            forKey: Key.lyricsDistanceBlurScale
        ) as? Double ?? Self.defaultLyricsDistanceBlurScale
        lyricsDistanceBlurScale = min(
            max(
                storedLyricsDistanceBlurScale,
                Self.lyricsDistanceBlurScaleRange.lowerBound
            ),
            Self.lyricsDistanceBlurScaleRange.upperBound
        )
        let storedLyricsHiddenInterfaceBlurScale = defaults.object(
            forKey: Key.lyricsHiddenInterfaceBlurScale
        ) as? Double ?? Self.defaultLyricsHiddenInterfaceBlurScale
        lyricsHiddenInterfaceBlurScale = min(
            max(
                storedLyricsHiddenInterfaceBlurScale,
                Self.lyricsDistanceBlurScaleRange.lowerBound
            ),
            Self.lyricsDistanceBlurScaleRange.upperBound
        )
        lyricsDimAmount = defaults.object(forKey: Key.lyricsDimAmount) as? Double
            ?? Self.defaultLyricsDimAmount
        lyricsTapToSeek = defaults.object(forKey: Key.lyricsTapToSeek) as? Bool ?? true
        lyricsLongPressToShare = defaults.object(
            forKey: Key.lyricsLongPressToShare
        ) as? Bool ?? true
        lyricsWordByWord = defaults.object(forKey: Key.lyricsWordByWord) as? Bool ?? true
        lyricsPseudoWordByWord = defaults.object(forKey: Key.lyricsPseudoWordByWord) as? Bool ?? false
        lyricsDuetLayoutEnabled = defaults.object(
            forKey: Key.lyricsDuetLayoutEnabled
        ) as? Bool ?? true
        lyricsLiftMode = LyricsLiftMode(
            rawValue: defaults.string(forKey: Key.lyricsLiftMode) ?? ""
        ) ?? Self.defaultLyricsLiftMode
        let storedLyricsHighlightGradientWidth = defaults.object(
            forKey: Key.lyricsHighlightGradientWidth
        ) as? Double ?? Self.defaultLyricsHighlightGradientWidth
        lyricsHighlightGradientWidth = min(
            max(
                storedLyricsHighlightGradientWidth,
                Self.lyricsHighlightGradientWidthRange.lowerBound
            ),
            Self.lyricsHighlightGradientWidthRange.upperBound
        )
        let storedLyricsHighlightGradientReduction = defaults.object(
            forKey: Key.lyricsHighlightGradientReduction
        ) as? Double ?? Self.defaultLyricsHighlightGradientReduction
        lyricsHighlightGradientReduction = min(
            max(
                storedLyricsHighlightGradientReduction,
                Self.lyricsHighlightGradientReductionRange.lowerBound
            ),
            Self.lyricsHighlightGradientReductionRange.upperBound
        )
        lyricsInterludeCountdownEnabled = defaults.object(forKey: Key.lyricsInterludeCountdownEnabled) as? Bool ?? true
        lyricsRefreshRate = LyricsRefreshRate(rawValue: defaults.object(forKey: Key.lyricsRefreshRate) as? Int ?? 0) ?? .defaultValue
        lyricsGlowEnabled = defaults.object(forKey: Key.lyricsGlowEnabled) as? Bool ?? true
        lyricsLongSyllableDetectionMode =
            LyricsLongSyllableDetectionMode(
                rawValue: defaults.string(
                    forKey: Key.lyricsLongSyllableDetectionMode
                ) ?? ""
            ) ?? Self.defaultLyricsLongSyllableDetectionMode
        lyricsGlowLongSyllablesOnly = defaults.object(
            forKey: Key.lyricsGlowLongSyllablesOnly
        ) as? Bool ?? Self.defaultLyricsGlowLongSyllablesOnly
        let storedLongSyllableDurationThreshold = defaults.object(
            forKey: Key.lyricsLongSyllableDurationThreshold
        ) as? Double ?? Self.defaultLyricsLongSyllableDurationThreshold
        lyricsLongSyllableDurationThreshold = min(
            max(
                storedLongSyllableDurationThreshold,
                Self.lyricsLongSyllableDurationThresholdRange.lowerBound
            ),
            Self.lyricsLongSyllableDurationThresholdRange.upperBound
        )
        let storedLyricsLongToneExpansionAmount = defaults.object(
            forKey: Key.lyricsLongToneExpansionAmount
        ) as? Double ?? Self.defaultLyricsLongToneExpansionAmount
        lyricsLongToneExpansionAmount = min(
            max(
                storedLyricsLongToneExpansionAmount,
                Self.lyricsLongToneExpansionAmountRange.lowerBound
            ),
            Self.lyricsLongToneExpansionAmountRange.upperBound
        )
        lyricsGlowIntensity = defaults.object(forKey: Key.lyricsGlowIntensity) as? Double ?? 1
        lyricsRomanizationEnabled = defaults.object(
            forKey: Key.lyricsRomanizationEnabled
        ) as? Bool ?? true
        lyricsRomanizationFontScale = defaults.object(
            forKey: Key.lyricsRomanizationFontScale
        ) as? Double ?? Self.defaultLyricsRomanizationFontScale
        lyricsRomanizationOpacity = defaults.object(
            forKey: Key.lyricsRomanizationOpacity
        ) as? Double ?? Self.defaultLyricsRomanizationOpacity
        lyricsRomanizationDisplayMode = LyricsTranslationDisplayMode(
            rawValue: defaults.string(
                forKey: Key.lyricsRomanizationDisplayMode
            ) ?? ""
        ) ?? .allLines
        lyricsTranslationEnabled = defaults.object(forKey: Key.lyricsTranslationEnabled) as? Bool ?? true
        lyricsTranslationDisplayMode = LyricsTranslationDisplayMode(
            rawValue: defaults.string(forKey: Key.lyricsTranslationDisplayMode) ?? ""
        ) ?? .focusedLine
        lyricsTranslationFontScale = defaults.object(
            forKey: Key.lyricsTranslationFontScale
        ) as? Double ?? Self.defaultLyricsTranslationFontScale
        lyricsTranslationOpacity = defaults.object(
            forKey: Key.lyricsTranslationOpacity
        ) as? Double ?? Self.defaultLyricsTranslationOpacity
        lyricsAutoFollow = defaults.object(forKey: Key.lyricsAutoFollow) as? Bool ?? true
        lyricsFollowDelay = defaults.object(forKey: Key.lyricsFollowDelay) as? Double ?? 3
        let storedLyricsFocusPosition = defaults.object(
            forKey: Key.lyricsFocusPosition
        ) as? Double ?? Self.defaultLyricsFocusPosition
        lyricsFocusPosition = min(
            max(
                storedLyricsFocusPosition,
                Self.lyricsFocusPositionRange.lowerBound
            ),
            Self.lyricsFocusPositionRange.upperBound
        )
        let storedFocusCascadeDelay = defaults.object(
            forKey: Key.lyricsFocusCascadeDelay
        ) as? Double ?? Self.defaultLyricsFocusCascadeDelay
        lyricsFocusCascadeDelay = min(
            max(
                storedFocusCascadeDelay,
                Self.lyricsFocusCascadeDelayRange.lowerBound
            ),
            Self.lyricsFocusCascadeDelayRange.upperBound
        )
        let storedFocusCascadeDelayIncrease = defaults.object(
            forKey: Key.lyricsFocusCascadeDelayIncrease
        ) as? Double ?? Self.defaultLyricsFocusCascadeDelayIncrease
        lyricsFocusCascadeDelayIncrease = min(
            max(
                storedFocusCascadeDelayIncrease,
                Self.lyricsFocusCascadeDelayIncreaseRange.lowerBound
            ),
            Self.lyricsFocusCascadeDelayIncreaseRange.upperBound
        )
        let storedFocusCascadeFollowingDelay = defaults.object(
            forKey: Key.lyricsFocusCascadeFollowingDelay
        ) as? Double ?? Self.defaultLyricsFocusCascadeFollowingDelay
        lyricsFocusCascadeFollowingDelay = min(
            max(
                storedFocusCascadeFollowingDelay,
                Self.lyricsFocusCascadeFollowingDelayRange.lowerBound
            ),
            Self.lyricsFocusCascadeFollowingDelayRange.upperBound
        )
        let storedFocusCascadeCatchUpRatio = defaults.object(
            forKey: Key.lyricsFocusCascadeCatchUpRatio
        ) as? Double ?? Self.defaultLyricsFocusCascadeCatchUpRatio
        lyricsFocusCascadeCatchUpRatio = min(
            max(
                storedFocusCascadeCatchUpRatio,
                Self.lyricsFocusCascadeCatchUpRatioRange.lowerBound
            ),
            Self.lyricsFocusCascadeCatchUpRatioRange.upperBound
        )
        let storedFocusCascadeChaseSpeedGradient = defaults.object(
            forKey: Key.lyricsFocusCascadeChaseSpeedGradient
        ) as? Double ?? Self.defaultLyricsFocusCascadeChaseSpeedGradient
        lyricsFocusCascadeChaseSpeedGradient = min(
            max(
                storedFocusCascadeChaseSpeedGradient,
                Self.lyricsFocusCascadeChaseSpeedGradientRange.lowerBound
            ),
            Self.lyricsFocusCascadeChaseSpeedGradientRange.upperBound
        )
        lyricsFocusCascadeBounceEnabled = defaults.object(
            forKey: Key.lyricsFocusCascadeBounceEnabled
        ) as? Bool ?? Self.defaultLyricsFocusCascadeBounceEnabled
        let storedFocusCascadeBounce = defaults.object(
            forKey: Key.lyricsFocusCascadeBounce
        ) as? Double ?? Self.defaultLyricsFocusCascadeBounce
        lyricsFocusCascadeBounce = min(
            max(
                storedFocusCascadeBounce,
                Self.lyricsFocusCascadeBounceRange.lowerBound
            ),
            Self.lyricsFocusCascadeBounceRange.upperBound
        )
        let storedFocusCascadeBounceGradient = defaults.object(
            forKey: Key.lyricsFocusCascadeBounceGradient
        ) as? Double ?? Self.defaultLyricsFocusCascadeBounceGradient
        lyricsFocusCascadeBounceGradient = min(
            max(
                storedFocusCascadeBounceGradient,
                Self.lyricsFocusCascadeBounceGradientRange.lowerBound
            ),
            Self.lyricsFocusCascadeBounceGradientRange.upperBound
        )
        lyricsFocusScaleBounceEnabled = defaults.object(
            forKey: Key.lyricsFocusScaleBounceEnabled
        ) as? Bool ?? Self.defaultLyricsFocusScaleBounceEnabled
        let storedFocusScaleBounce = defaults.object(
            forKey: Key.lyricsFocusScaleBounce
        ) as? Double ?? Self.defaultLyricsFocusScaleBounce
        lyricsFocusScaleBounce = min(
            max(
                storedFocusScaleBounce,
                Self.lyricsFocusScaleBounceRange.lowerBound
            ),
            Self.lyricsFocusScaleBounceRange.upperBound
        )
        let storedFocusScaleBounceDuration = defaults.object(
            forKey: Key.lyricsFocusScaleBounceDuration
        ) as? Double ?? Self.defaultLyricsFocusScaleBounceDuration
        lyricsFocusScaleBounceDuration = min(
            max(
                storedFocusScaleBounceDuration,
                Self.lyricsFocusScaleBounceDurationRange.lowerBound
            ),
            Self.lyricsFocusScaleBounceDurationRange.upperBound
        )
        let storedFocusCascadeDuration = defaults.object(
            forKey: Key.lyricsFocusCascadeDuration
        ) as? Double
            ?? defaults.object(
                forKey: Key.legacyLyricsFocusCascadeMinimumBounceDuration
            ) as? Double
            ?? Self.defaultLyricsFocusCascadeDuration
        lyricsFocusCascadeDuration = min(
            max(
                storedFocusCascadeDuration,
                Self.lyricsFocusCascadeDurationRange.lowerBound
            ),
            Self.lyricsFocusCascadeDurationRange.upperBound
        )
        let storedFocusSnapThreshold = defaults.object(
            forKey: Key.lyricsFocusSnapThreshold
        ) as? Double ?? Self.defaultLyricsFocusSnapThreshold
        lyricsFocusSnapThreshold = min(
            max(
                storedFocusSnapThreshold,
                Self.lyricsFocusSnapThresholdRange.lowerBound
            ),
            Self.lyricsFocusSnapThresholdRange.upperBound
        )
        let storedFocusColorLeadTime = defaults.object(
            forKey: Key.lyricsFocusColorLeadTime
        ) as? Double ?? Self.defaultLyricsFocusColorLeadTime
        lyricsFocusColorLeadTime = min(
            max(
                storedFocusColorLeadTime,
                Self.lyricsFocusColorLeadTimeRange.lowerBound
            ),
            Self.lyricsFocusColorLeadTimeRange.upperBound
        )
        lyricsAdvanceTime = defaults.object(forKey: Key.lyricsAdvanceTime) as? Double ?? 0.2
        lyricsAdvanceTimeAppliesToWordByWord =
            defaults.object(
                forKey: Key.lyricsAdvanceTimeAppliesToWordByWord
            ) as? Bool ?? false
    }
}
