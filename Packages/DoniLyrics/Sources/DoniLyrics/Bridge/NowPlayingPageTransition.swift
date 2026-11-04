import SwiftUI

public enum NowPlayingPageTransition {
    static let motion = NowPlayingMotionSpec.appleMusic26.page

    /// The curve the portrait cover travels on between the artwork page's frame and the header's,
    /// which is the one thing outside the package that needs a number from `motion`.
    public static var artworkResizeAnimation: Animation {
        motion.artworkResize.animation
    }

    public static var animation: Animation {
        motion.selection.animation
    }

    public static var directLyricsQueueContentScale: CGFloat {
        motion.directAlternateContentScale
    }

    public static var lyricsEntranceOffset: CGFloat {
        motion.lyricsTravel
    }

    public static var queueOffset: CGFloat {
        motion.queueTravel
    }

    public static func content(
        for page: NowPlayingPage,
        entersFromHiddenQueue: Bool,
        reducesMotion: Bool
    ) -> AnyTransition {
        if reducesMotion {
            return .opacity
        }

        if entersFromHiddenQueue {
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            )
        }

        switch page {
        case .artwork:
            return directionalOffsetAndOpacity(
                insertionY: motion.artworkDetailsTravel,
                removalY: motion.artworkDetailsTravel
            )
        case .lyrics:
            return .asymmetric(
                insertion: .opacity,
                removal:
                    offsetAndOpacity(y: lyricsEntranceOffset)
                    .animation(motion.outgoing.animation)
            )
        case .queue:
            return stagedOffsetAndOpacity(y: queueOffset)
        }
    }

    public static func songHeader(reducesMotion: Bool) -> AnyTransition {
        guard !reducesMotion else { return .opacity }
        return .asymmetric(
            insertion:
                offsetAndOpacity(y: motion.songHeaderTravel)
                .animation(motion.songHeaderIncoming.animation),
            removal:
                offsetAndOpacity(y: motion.songHeaderTravel)
                .animation(motion.outgoing.animation)
        )
    }

    public static func selectionAnimation(
        from source: NowPlayingPage,
        to destination: NowPlayingPage
    ) -> Animation {
        if isDirectLyricsQueueTransition(
            from: source,
            to: destination
        ) {
            return motion.directAlternate.animation
        }
        return animation
    }

    static func residentQueueAnimation(
        from source: NowPlayingPage,
        to destination: NowPlayingPage,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        if isDirectLyricsQueueTransition(
            from: source,
            to: destination
        ) {
            return motion.directAlternate.animation
        }
        if destination == .queue {
            return motion.delayedResidentEntrance.animation
        }
        if source == .queue {
            return motion.outgoing.animation
        }
        return nil
    }

    static func residentLyricsSpatialAnimation(
        for transition: NowPlayingTransitionContext?,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        return motion
            .residentLyricsSpatialAnimation(for: transition)?
            .animation
    }

    static func residentLyricsOpacityAnimation(
        for transition: NowPlayingTransitionContext?,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else { return nil }
        return motion
            .residentLyricsOpacityAnimation(for: transition)?
            .animation
    }

    public static func isDirectLyricsQueueTransition(
        from source: NowPlayingPage,
        to destination: NowPlayingPage
    ) -> Bool {
        source == .lyrics && destination == .queue
            || source == .queue && destination == .lyrics
    }

    public static func directAlternateContent(
        reducesMotion: Bool
    ) -> AnyTransition {
        guard !reducesMotion else { return .opacity }
        return .scale(
            scale: directLyricsQueueContentScale,
            anchor: .center
        )
        .combined(with: .opacity)
    }

    private static func stagedOffsetAndOpacity(
        y: CGFloat
    ) -> AnyTransition {
        directionalOffsetAndOpacity(
            insertionY: y,
            removalY: y
        )
    }

    private static func directionalOffsetAndOpacity(
        insertionY: CGFloat,
        removalY: CGFloat
    ) -> AnyTransition {
        .asymmetric(
            insertion:
                offsetAndOpacity(y: insertionY)
                .animation(motion.incoming.animation),
            removal:
                offsetAndOpacity(y: removalY)
                .animation(motion.outgoing.animation)
        )
    }

    private static func offsetAndOpacity(
        y: CGFloat
    ) -> AnyTransition {
        .offset(y: y).combined(with: .opacity)
    }
}
