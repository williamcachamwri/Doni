import Foundation

struct NowPlayingTransitionContext: Equatable, Identifiable, Sendable {
    let id: UUID
    let source: NowPlayingPage
    let destination: NowPlayingPage
    let isDirectLyricsQueueTransition: Bool
    let entersFromHiddenQueue: Bool
    let usesStagedLyricsEntrance: Bool
    let interruptsLyricsExit: Bool

    init(
        id: UUID = UUID(),
        source: NowPlayingPage,
        destination: NowPlayingPage,
        entersFromHiddenQueue: Bool,
        usesStagedLyricsEntrance: Bool,
        interruptsLyricsExit: Bool
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        isDirectLyricsQueueTransition =
            source == .lyrics && destination == .queue
            || source == .queue && destination == .lyrics
        self.entersFromHiddenQueue = entersFromHiddenQueue
        self.usesStagedLyricsEntrance = usesStagedLyricsEntrance
        self.interruptsLyricsExit = interruptsLyricsExit
    }
}

struct NowPlayingPendingLyricsEntrance: Equatable, Sendable {
    let requestID: UUID
    let notBefore: ContinuousClock.Instant
    let fallbackAt: ContinuousClock.Instant
}
