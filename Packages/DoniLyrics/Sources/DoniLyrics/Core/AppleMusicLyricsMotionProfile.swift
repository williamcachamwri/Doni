#if os(iOS)
import Foundation

/// Internal reconstruction of motion constants observed in Apple Music 26.6.
/// Property names describe inferred behavior; they are not public Apple API.
public struct AppleMusicLyricsMotionProfile: Equatable, Sendable {
    public let firstLineStartOffset: Double
    /// Percentage of the effective viewport height used for synced-line
    /// positioning before subtracting the lyric font ascender.
    public let selectedLineTopRelativePercent: Double
    /// Static-mode vertical insets; these do not combine with synced mode.
    public let staticTopContentInset: Double
    public let staticBottomContentInset: Double
    public let paragraphSpacing: Double
    public let lineSpacing: Double
    public let backgroundVocalsTopSpacing: Double
    public let backgroundVocalsDeselectedScale: Double
    public let backgroundVocalsFontCoefficient: Double
    public let translationBackgroundVocalsFontCoefficient: Double
    public let transliterationBackgroundVocalsFontCoefficient: Double
    public let cascadeDelay: TimeInterval
    public let deselectedScale: Double
    public let nonFocusedBlurRadius: Double
    public let maximumNonFocusedBlurRadius: Double
    public let selectedTextOpacity: Double
    public let selectedUpcomingTextOpacity: Double
    public let deselectedTextOpacity: Double
    public let increasedContrastSelectedTextOpacity: Double
    public let increasedContrastSelectedUpcomingTextOpacity: Double
    public let increasedContrastDeselectedTextOpacity: Double
    /// The native line-focus blur animator also drives its brightness filter.
    public let focusBlurTransitionDuration: TimeInterval
    public let focusBlurTransitionControlPoint1X: Double
    public let focusBlurTransitionControlPoint1Y: Double
    public let focusBlurTransitionControlPoint2X: Double
    public let focusBlurTransitionControlPoint2Y: Double
    public let animationHeadstart: TimeInterval
    /// Timed glyph/syllable emphasis range. Never scale the complete row.
    public let emphasisScaleRange: ClosedRange<Double>
    public let lineFinishProgressAnimationDuration: TimeInterval
    public let lineProgressionGradientFeather: Double
    public let glowRadius: Double
    public let syllableLift: Double
    /// Default focus and line-change solver values observed in Lyrics.Specs.
    public let lineChangeSpring: LyricPhysicalSpringParameters
    /// Solver values observed on the forced/special line catch-up path.
    public let forcedLineCatchUpSpring: LyricPhysicalSpringParameters
    /// Translation/transliteration reveal solver values.
    public let supplementalTextShowSpring: LyricPhysicalSpringParameters
    /// Translation/transliteration removal solver values.
    public let supplementalTextHideSpring: LyricPhysicalSpringParameters

    public static let iOS26_6 = Self(
        firstLineStartOffset: 60,
        selectedLineTopRelativePercent: 12,
        staticTopContentInset: 22,
        staticBottomContentInset: 30,
        paragraphSpacing: 39,
        lineSpacing: 25,
        backgroundVocalsTopSpacing: 15,
        backgroundVocalsDeselectedScale: 0.9,
        backgroundVocalsFontCoefficient: 0.63,
        translationBackgroundVocalsFontCoefficient: 0.36,
        transliterationBackgroundVocalsFontCoefficient: 0.27,
        cascadeDelay: 0.05,
        deselectedScale: 0.98,
        nonFocusedBlurRadius: 3,
        maximumNonFocusedBlurRadius: 4,
        selectedTextOpacity: 1,
        selectedUpcomingTextOpacity: 0.35,
        deselectedTextOpacity: 0.175,
        increasedContrastSelectedTextOpacity: 1,
        increasedContrastSelectedUpcomingTextOpacity: 0.85,
        increasedContrastDeselectedTextOpacity: 0.4,
        focusBlurTransitionDuration: 0.12,
        focusBlurTransitionControlPoint1X: 0.33,
        focusBlurTransitionControlPoint1Y: 0,
        focusBlurTransitionControlPoint2X: 0.2,
        focusBlurTransitionControlPoint2Y: 0.1,
        animationHeadstart: 0.1,
        emphasisScaleRange: 1...1.14,
        lineFinishProgressAnimationDuration: 0.25,
        lineProgressionGradientFeather: 30,
        glowRadius: 5,
        syllableLift: 2,
        lineChangeSpring: LyricPhysicalSpringParameters(
            mass: 1,
            stiffness: 100,
            damping: 18
        ),
        forcedLineCatchUpSpring: LyricPhysicalSpringParameters(
            mass: 2,
            stiffness: 260,
            damping: 50
        ),
        supplementalTextShowSpring: LyricPhysicalSpringParameters(
            mass: 1,
            stiffness: 150,
            damping: 30
        ),
        supplementalTextHideSpring: LyricPhysicalSpringParameters(
            mass: 1,
            stiffness: 130,
            damping: 30
        )
    )

    public func dynamicSpring(
        sourceDuration: TimeInterval
    ) -> LyricPhysicalSpringParameters {
        AppleMusicLyricsDynamicSpring.parameters(
            sourceDuration: sourceDuration
        )
    }
}
#endif
