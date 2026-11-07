import CoreGraphics
import Foundation

/// Geometry and timing recovered from Music 26.6's
/// `InstrumentalContentLayer` and `LyricsSpecs` implementation.
public struct AppleMusicInterludeMotionProfile: Hashable, Sendable {
    public static let iOS26_6 = AppleMusicInterludeMotionProfile(
        dotCount: 3,
        dotLength: 12,
        dotMargin: 8,
        viewHeight: 40,
        fillLeadInDuration: 1,
        fillAnimationDuration: 0.8,
        fillStagger: 0.06,
        inactiveDotOpacity: 0.1,
        cueOutLeadTime: 1.8,
        cuePeakScale: 1.2,
        cuePeakDuration: 1,
        cueFadeDuration: 0.3,
        cueTerminalScale: 0.2,
        cueTerminalScaleDuration: 0.5,
        breathLowerScale: 0.9,
        breathUpperScale: 1.2,
        breathDelay: 0.2,
        breathAnimationInset: 0.4
    )

    public let dotCount: Int
    public let dotLength: CGFloat
    public let dotMargin: CGFloat
    public let viewHeight: CGFloat
    public let fillLeadInDuration: TimeInterval
    public let fillAnimationDuration: TimeInterval
    public let fillStagger: TimeInterval
    public let inactiveDotOpacity: Double
    public let cueOutLeadTime: TimeInterval
    public let cuePeakScale: CGFloat
    public let cuePeakDuration: TimeInterval
    public let cueFadeDuration: TimeInterval
    public let cueTerminalScale: CGFloat
    public let cueTerminalScaleDuration: TimeInterval
    public let breathLowerScale: CGFloat
    public let breathUpperScale: CGFloat
    public let breathDelay: TimeInterval
    public let breathAnimationInset: TimeInterval

    public var contentWidth: CGFloat {
        CGFloat(dotCount) * dotLength
            + CGFloat(max(dotCount - 1, 0)) * dotMargin
    }

    /// The recovered exit animation has finished visually before the
    /// following lyric's timestamp: fade ends after 1.3 seconds, while scale
    /// collapse ends after 1.5 seconds. The resident row remains in layout.
    public var visualExitDuration: TimeInterval {
        max(
            cuePeakDuration + cueFadeDuration,
            cuePeakDuration + cueTerminalScaleDuration
        )
    }

    /// Music uses deliberately out-of-bounds anchor points for the outside
    /// dots, causing them to spread at 1.2x and collapse inward at 0.2x.
    public func dotAnchorX(at index: Int) -> CGFloat {
        switch index {
        case 0:
            return 1.8
        case dotCount - 1:
            return -0.8
        default:
            return 0.5
        }
    }

    public func timing(
        for interlude: LyricInterlude
    ) -> AppleMusicInterludeMotionTiming {
        let startTime = interlude.startTime
        let endTime = max(interlude.countdownEndTime, startTime)
        let cueOutTime = max(startTime, endTime - cueOutLeadTime)
        let visualEndTime = min(
            endTime,
            cueOutTime + visualExitDuration
        )
        let activeDuration = max(cueOutTime - startTime, 0)
        let breathCount = max(floor(activeDuration * 0.25), 1)
        let breathHalfCycleDuration = activeDuration
            / breathCount
            * 0.5
        let fillStartTime = startTime + fillLeadInDuration
        let fillDuration = max(cueOutTime - fillStartTime, 0)
        let fillStageInterval = fillDuration / Double(dotCount)

        return AppleMusicInterludeMotionTiming(
            startTime: startTime,
            endTime: endTime,
            visualEndTime: visualEndTime,
            cueOutTime: cueOutTime,
            fillStartTime: fillStartTime,
            fillStageInterval: fillStageInterval,
            breathHalfCycleDuration: breathHalfCycleDuration
        )
    }
}

public struct AppleMusicInterludeMotionTiming: Hashable, Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let visualEndTime: TimeInterval
    public let cueOutTime: TimeInterval
    public let fillStartTime: TimeInterval
    public let fillStageInterval: TimeInterval
    public let breathHalfCycleDuration: TimeInterval
}
