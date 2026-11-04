import SwiftUI

public enum NowPlayingInterfaceTransition {
    public typealias ControlLayer = NowPlayingInterfaceLayer

    private static let motion = NowPlayingMotionSpec.appleMusic26.interface

    public static var utilityHiddenOffset: CGFloat {
        motion.utilityHiddenOffset
    }

    public static var utilityHiddenScale: CGFloat {
        motion.utilityHiddenScale
    }

    public static func interfaceAnimation(
        isVisible: Bool,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        return isVisible
            ? motion.coreShow.animation
            : motion.coreHide.animation
    }

    public static func utilityAnimation(
        isVisible: Bool,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        return isVisible
            ? motion.utilityShow.animation
            : motion.utilityHide.animation
    }

    public static func hiddenOffset(
        for layer: ControlLayer
    ) -> CGFloat {
        motion.layerMotion(for: layer).hiddenOffset
    }

    public static func controlAnimation(
        for layer: ControlLayer,
        isVisible: Bool,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }

        return motion.controlAnimation(
            for: layer,
            isVisible: isVisible
        ).animation
    }
}
