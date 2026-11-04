import AVFoundation
import MediaPlayer
import SwiftUI
import TelegramDesignSystem
import TdSession
import UIKit

/// The one thing that makes noise.
///
/// `AVAudioPlayer` rather than `AVPlayer`: these are whole files TDLib has already put on the
/// device, there is no streaming or DRM to negotiate, and a segment favourite needs a seek that
/// lands exactly. Background audio works because `UIBackgroundModes` lists `audio` and the
/// session is `.playback`, which is the only category that survives the app being suspended.
@MainActor
final class Player: ObservableObject {
    /// What the end of the queue is: an ending, a loop of the whole list, or a loop of this song.
    enum RepeatMode: Equatable, Sendable {
        case off, all, one
    }

    @Published private(set) var current: (any Playable)?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// True while the song is still being fetched — the row's bubble is a spinner for this.
    @Published private(set) var isFetchingFile = false
    /// The slice being played, when the user favoured one: the player holds itself inside it.
    @Published var segment: ClosedRange<Double>?
    /// The start of a cut the user is marking, before they have reached its end. Held here rather
    /// than in the panel because the panel's two pages — the chip and the queue's pill — both show
    /// it, and a cut marked on one has to read the same on the other.
    @Published private(set) var markIn: TimeInterval?
    /// The queue as the up-next page shows it, in the order it will be played.
    @Published private(set) var queue: [any Playable] = []
    /// Which row of `queue` is playing, so the page can mark it and a swipe can be answered.
    @Published private(set) var index = 0
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    /// The player's own volume, 0…1. `AVAudioPlayer` has a real one, which is why Doni's volume bar
    /// moves sound instead of being the prop the reference had to settle for.
    @Published var volume: Float = 1 {
        didSet {
            engine?.volume = volume
            publishNowPlaying(elapsed: elapsed)
        }
    }

    /// The order the list was played in, kept so turning shuffle off puts it back.
    private var source: [any Playable] = []
    private var engine: AVAudioPlayer?
    private var ticker: Timer?
    private var loading: Task<Void, Never>?
    /// The lock screen's cover, and the bitmap it was made from. See `artwork(for:)`.
    private var artworkItem: (uniqueId: String, image: UIImage, item: MPMediaItemArtwork)?
    /// Set once the session is authorized: a song is a `file_id` until TDLib puts it on the phone.
    private var downloader: TdFileDownloader?
    /// Where a file that has just landed is written down, so the row reads as downloaded next
    /// launch and the offline count in Settings is the truth.
    private let library: Library

    /// A repeat loop always has somewhere to go, so the next button is never idle while one is on.
    var hasNext: Bool { !queue.isEmpty && (index + 1 < queue.count || repeatMode != .off) }
    var hasPrevious: Bool { !queue.isEmpty && (index > 0 || repeatMode != .off) }

    func bind(_ downloader: TdFileDownloader?) {
        self.downloader = downloader
    }

    init(library: Library = .shared) {
        self.library = library
        // Background audio only survives if the category is `.playback` before the first file is
        // opened; `UIBackgroundModes` lists `audio` for the same reason.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
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
    func play(_ track: any Playable, in list: [any Playable]) {
        source = list
        queue = list
        index = list.firstIndex { $0.uniqueId == track.uniqueId } ?? 0
        segment = nil
        markIn = nil
        if isShuffled { shuffleAhead() }
        startCurrent()
    }

    /// Shuffle only ever touches what has not been heard: the rows behind the playhead stay where
    /// the user left them, so a flick of the pill never requeues a song already played.
    private func shuffleAhead() {
        guard index < queue.count else { return }
        let ahead = Array(queue[index...]).shuffled()
        queue.replaceSubrange(index..<queue.count, with: ahead)
    }

    func setShuffled(_ on: Bool) {
        guard on != isShuffled else { return }
        isShuffled = on
        if on {
            shuffleAhead()
        } else {
            // Back to the order the list was opened in, with this song still under the finger.
            let held = current?.uniqueId
            queue = source
            if let held { index = queue.firstIndex { $0.uniqueId == held } ?? index }
        }
    }

    /// The repeat pill walks the three states in the order the reference draws them.
    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: The queue page

    /// Tapping a row of the up-next page plays that row.
    func play(at position: Int) {
        guard queue.indices.contains(position), position != index else { return }
        index = position
        startCurrent()
    }

    /// "Play next" from a row: the song goes in directly behind this one, and a queue that already
    /// holds it moves rather than duplicates it.
    func playNext(_ track: any Playable) {
        var target = queue
        if let already = target.firstIndex(where: { $0.uniqueId == track.uniqueId }) {
            target.remove(at: already)
        }
        let place = min(index + 1, target.count)
        target.insert(track, at: place)
        set(order: target)
    }

    /// Dragging a row somewhere else. A hand-made order is the user's, so it also becomes the order
    /// a shuffle-off goes back to.
    func move(from offsets: IndexSet, to destination: Int) {
        guard !offsets.isEmpty else { return }
        var target = queue
        target.move(fromOffsets: offsets, toOffset: destination)
        set(order: target, pinAsSource: true)
    }

    /// Taking rows out of the queue. The song that is playing keeps playing even when its row goes:
    /// the queue is a plan for what comes next, not the thing making noise.
    func remove(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        let leaving = Set(offsets.map { queue[$0].uniqueId })
        source.removeAll { leaving.contains($0.uniqueId) }
        var target = queue
        target.remove(atOffsets: offsets)
        set(order: target)
    }

    /// Installs a new queue order and keeps the playhead on the song it was on.
    private func set(order: [any Playable], pinAsSource: Bool = false) {
        let held = current?.uniqueId
        queue = order
        if pinAsSource { source = order }
        if let held, let found = order.firstIndex(where: { $0.uniqueId == held }) {
            index = found
        } else {
            index = min(index, max(order.count - 1, 0))
        }
    }

    /// The rows still ahead of the playhead — what the up-next page lists. MeloX's
    /// `unplayedQueueIndices` (`PlayerStore.swift:89`) is `upcomingIndices(wraps: false)`
    /// (`PlaybackQueue.swift:66-78`): a repeat never re-offers what has already been heard, so the
    /// page shows the tail of the queue and nothing more.
    var upcomingIndices: [Int] {
        guard !queue.isEmpty else { return [] }
        return Array(queue.indices.dropFirst(min(index + 1, queue.count)))
    }

    /// The glyph the queue button wears while it is not the page on screen — MeloX's
    /// `queueModeBadgeSystemImage` (`PlayerStore.swift:97`) and
    /// `QueuePlaybackModeIndicator.systemImage` (`PlaybackQueue.swift:33-40`).
    var queueModeBadgeSystemImage: String? {
        if repeatMode == .one { return "repeat.1" }
        if repeatMode == .all { return "repeat" }
        if isShuffled { return "shuffle" }
        return nil
    }

    /// MeloX's own mapping (`PlaybackQueue.swift:10-15`): off and repeat-all share the glyph, and
    /// only repeat-one earns the `.1`.
    var repeatSystemImage: String {
        repeatMode == .one ? "repeat.1" : "repeat"
    }

    /// Dragging on the up-next page. Its rows are the queue's tail, so the offsets the list reports
    /// are lifted onto the whole queue by the number of rows the page never shows.
    func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        let ahead = min(index + 1, queue.count)
        move(from: IndexSet(offsets.map { $0 + ahead }), to: destination + ahead)
    }

    /// The same track again, but only for the slice the user favourited.
    func play(segment: ClosedRange<Double>, of track: any Playable) {
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
        artworkItem = nil
        current = nil
        queue = []
        source = []
        index = 0
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

    /// Forward, and past the last row the loop decides what happens: a repeat walks back to the
    /// start, no repeat stops with the queue.
    func next() {
        guard hasNext else { return }
        index = index + 1 < queue.count ? index + 1 : 0
        startCurrent()
    }

    func previous() {
        guard hasPrevious else { return }
        // A song more than three seconds in goes back to its own start first, the way every player
        // the user already knows behaves; the press after that leaves it.
        if elapsed > 3 {
            seek(to: 0)
            return
        }
        index = index > 0 ? index - 1 : queue.count - 1
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

    // MARK: Cutting

    /// The first press of a cut: the song's current second becomes where the slice starts.
    func markStart() {
        markIn = elapsed
    }

    /// The second press: wherever the song has reached since. A mark that has not moved forward is
    /// not a slice, so it is refused rather than saved as a zero-length one.
    func markEnd() {
        guard let started = markIn, elapsed > started else { return }
        segment = started...elapsed
        markIn = nil
    }

    /// Letting a cut go, whether it was only marked or already held.
    func clearCut() {
        segment = nil
        markIn = nil
    }

    // MARK: Loading

    private func startCurrent() {
        guard index >= 0, index < queue.count else { return }
        let track = queue[index]
        loading?.cancel()
        // The song before this one is put down now rather than when the next arrives: an
        // `AVAudioPlayer` holds its file open, a one-hour mix is a hundred and forty megabytes, and
        // the fetch below can take a minute — a gap in which the app was carrying two of them at
        // once with only one of them audible.
        engine?.stop()
        engine = nil
        // A cut is a decision about one song, so it does not travel: the row the chip is describing
        // is the row under the finger, and a new song has no slice until one is marked on it.
        segment = nil
        markIn = nil
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
            // The path that played is the one written back: a stored path that turned out to be
            // stale is corrected here rather than left to fail again next time.
            library.recordDownload(path: onDisk, uniqueId: track.uniqueId)
            open(path: onDisk, track: track)
        }
    }

    private func open(path: String, track: any Playable) {
        let url = URL(fileURLWithPath: path)
        guard let engine = try? AVAudioPlayer(contentsOf: url) else {
            isFetchingFile = false
            return
        }
        self.engine = engine
        self.duration = engine.duration
        self.isFetchingFile = false
        // A fresh `AVAudioPlayer` starts at full, so the slider's position has to be written into
        // it before the first sample goes out — otherwise the second song of a queue jumps louder.
        engine.volume = volume
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
            } else if repeatMode == .one {
                engine.currentTime = 0
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

    private func publishNowPlaying(elapsed: TimeInterval, track: (any Playable)? = nil) {
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
        if let artwork = artwork(for: shown) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The lock screen's cover, rebuilt only when the picture behind it actually changed.
    ///
    /// `nowPlayingInfo` crosses into another process and the ticker writes it four times a second,
    /// so an hour of listening used to hand out fourteen thousand fresh `MPMediaItemArtwork` objects
    /// holding fourteen thousand copies of one bitmap — which is how a player that plays fine ends up
    /// killed by the system an hour in. The cache asks for the hero's size because that is the
    /// biggest the lock screen can draw, and takes the row's minithumbnail only when nothing better
    /// has arrived, because an artwork slot that is soft beats one that is empty.
    private func artwork(for track: any Playable) -> MPMediaItemArtwork? {
        let image = CoverArtwork.shared.sharp(for: track, side: MusicArtworkMetrics.heroSide)
            ?? CoverArtwork.shared.mini(for: track)
        guard let image else { return nil }
        if let held = artworkItem, held.uniqueId == track.uniqueId, held.image === image {
            return held.item
        }
        let item = Self.mediaArtwork(image)
        artworkItem = (track.uniqueId, image, item)
        return item
    }

    /// The artwork, built away from the main actor on purpose.
    ///
    /// MediaPlayer does not ask for the picture on the thread that handed it the dictionary: it
    /// calls the handler from its own queue, inside `_onQueue_pushNowPlayingInfoAndRetry:` →
    /// `jpegDataWithSize:`. A closure written in a `@MainActor` function carries that isolation, so
    /// the call trips `dispatch_assert_queue` and the process dies of a `SIGTRAP` — which is what
    /// every one of today's crash reports says, and why it was only ever songs *with* a cover that
    /// died: a song without one never puts an artwork slot in the dictionary at all. The SDK does not
    /// catch it because `requestHandler:` is not declared `@Sendable`.
    private nonisolated static func mediaArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
