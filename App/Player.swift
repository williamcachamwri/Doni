import AVFoundation
import MediaPlayer
import SwiftUI
import TdSession

/// The one thing that makes noise.
///
/// `AVAudioPlayer` rather than `AVPlayer`: these are whole files TDLib has already put on the
/// device, there is no streaming or DRM to negotiate, and a segment favourite needs a seek that
/// lands exactly. Background audio works because `UIBackgroundModes` lists `audio` and the
/// session is `.playback`, which is the only category that survives the app being suspended.
@MainActor
final class Player: ObservableObject {
    @Published private(set) var current: TdTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// True while the song is still being fetched — the row's bubble is a spinner for this.
    @Published private(set) var isFetchingFile = false
    /// The slice being played, when the user favoured one: the player holds itself inside it.
    @Published var segment: ClosedRange<Double>?
    /// Queue order, so the list can mark the row it is on.
    @Published private(set) var queueCount = 0

    private var queue: [TdTrack] = []
    private var index = 0
    private var engine: AVAudioPlayer?
    private var ticker: Timer?
    private var loading: Task<Void, Never>?
    /// Set once the session is authorized: a song is a `file_id` until TDLib puts it on the phone.
    private var downloader: TdFileDownloader?

    var hasNext: Bool { index + 1 < queue.count }
    var hasPrevious: Bool { index > 0 }

    func bind(_ downloader: TdFileDownloader?) {
        self.downloader = downloader
    }

    init() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in
            Task { @MainActor in self.resume() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in self.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in self.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in self.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in self.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self.seek(to: event.positionTime) }
            return .success
        }
    }

    /// Plays one track out of `list`, fetching its file first if the phone does not have it.
    /// The whole list becomes the queue so next/previous walk the channel the way a listener
    /// expects, newest first.
    func play(_ track: TdTrack, in list: [TdTrack]) {
        queue = list
        index = list.firstIndex(of: track) ?? 0
        queueCount = list.count
        segment = nil
        startCurrent()
    }

    /// The same track again, but only for the slice the user favourited.
    func play(segment: ClosedRange<Double>, of track: TdTrack) {
        play(track, in: [track])
        self.segment = segment
    }

    func stop() {
        loading?.cancel()
        loading = nil
        ticker?.invalidate()
        ticker = nil
        engine?.stop()
        engine = nil
        current = nil
        isPlaying = false
        isFetchingFile = false
        elapsed = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        engine?.pause()
        isPlaying = false
        publishNowPlaying(elapsed: elapsed)
    }

    func resume() {
        guard engine != nil else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // A session that will not activate is not a reason to lose the row that is playing.
        }
        engine?.play()
        isPlaying = true
        publishNowPlaying(elapsed: elapsed)
    }

    func next() {
        guard hasNext else { return }
        index += 1
        startCurrent()
    }

    func previous() {
        guard hasPrevious else { return }
        index -= 1
        startCurrent()
    }

    func seek(to seconds: TimeInterval) {
        let floor = segment?.lowerBound ?? 0
        let ceiling = segment?.upperBound ?? (engine?.duration ?? 0)
        let clamped = min(max(seconds, floor), ceiling)
        engine?.currentTime = clamped
        elapsed = clamped
        publishNowPlaying(elapsed: clamped)
    }

    // MARK: Loading

    private func startCurrent() {
        guard index >= 0, index < queue.count else { return }
        let track = queue[index]
        loading?.cancel()
        engine?.stop()
        current = track
        elapsed = 0
        duration = Double(track.duration ?? 0)
        isFetchingFile = track.localPath == nil

        let path = track.localPath
        let fileId = track.fileId
        let downloader = self.downloader
        loading = Task {
            let onDisk: String?
            if let path {
                onDisk = path
            } else {
                onDisk = await downloader?.path(fileId: fileId,
                                                priority: TdFileDownloader.audioPriority)
            }
            guard !Task.isCancelled, let onDisk else {
                isFetchingFile = false
                return
            }
            open(path: onDisk, track: track)
        }
    }

    private func open(path: String, track: TdTrack) {
        let url = URL(fileURLWithPath: path)
        guard let engine = try? AVAudioPlayer(contentsOf: url) else {
            isFetchingFile = false
            return
        }
        self.engine = engine
        self.duration = engine.duration
        self.isFetchingFile = false
        if let segment {
            engine.currentTime = segment.lowerBound
            elapsed = segment.lowerBound
        }
        engine.prepareToPlay()
        engine.play()
        isPlaying = true
        startTicker()
        publishNowPlaying(elapsed: engine.currentTime, track: track)
    }

    /// A timer rather than the delegate: `AVAudioPlayerDelegate` methods are nonisolated, and
    /// the tick this app needs for a progress bar is the same one that notices the song ended.
    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let engine else { return }
        let end = segment?.upperBound ?? engine.duration
        if engine.currentTime >= end - 0.05 {
            if let segment {
                // A favourited slice loops: that is the point of saving three minutes of a
                // one-hour set.
                engine.currentTime = segment.lowerBound
            } else if hasNext {
                next()
                return
            } else {
                pause()
                engine.currentTime = 0
            }
        }
        elapsed = engine.currentTime
        if isPlaying { publishNowPlaying(elapsed: engine.currentTime) }
    }

    // MARK: Lock screen and control centre

    private func publishNowPlaying(elapsed: TimeInterval, track: TdTrack? = nil) {
        let shown = track ?? current
        guard let shown else { return }
        let artist = shown.displayPerformer.isEmpty ? "Doni" : shown.displayPerformer
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: shown.displayTitle,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            // The lock screen runs its own clock from this rate, so 0 is what holds it still.
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let artwork = CoverArtwork.shared.image(for: shown) {
            // The lock screen asks for the artwork at whatever size it has; the bitmap we
            // already decoded for the row is the one it gets back.
            let size = artwork.size
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
