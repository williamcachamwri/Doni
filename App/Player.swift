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
    ///
    /// A `String` raw value because the mode is written into the resume snapshot, where the
    /// reference keeps it as text (`PlaybackQueue.swift:3`, `PlaybackPersistence.swift:7`).
    enum RepeatMode: String, Equatable, Sendable, Codable {
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
            persist()
        }
    }

    /// The order the list was played in, kept so turning shuffle off puts it back.
    private var source: [any Playable] = []
    private var engine: AVAudioPlayer?
    private var ticker: Timer?
    /// Held because `AVAudioPlayer.delegate` is a weak reference, and because one watcher outlives
    /// every song: what it says is only "this file has run out".
    private lazy var endWatcher = SongEndWatcher { [weak self] in
        Task { @MainActor in self?.songEnded() }
    }
    private var loading: Task<Void, Never>?
    /// The lead-time fetch of the song queued behind this one, and the song it was started for. The
    /// id is what stops a timer that fires four times a second asking for the same file forty times
    /// over.
    private var prefetch: Task<Void, Never>?
    private var prefetchingId: String?
    /// The second last written into the resume snapshot, so the clock saves once per second of
    /// listening and not four times (`PlayerStore.swift:190, 1231-1235`).
    private var lastPersistedSecond = -1
    /// `restore()` runs once per launch, however many views ask for it
    /// (`PlayerStore.swift:184, 277-278`).
    private var hasRestoredPlayback = false
    /// A play press that arrived while the file was still being fetched: the load honours it when
    /// it lands, because the press meant it and the row was only too early.
    private var wantsPlayWhenReady = false
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

    /// The row the next button would land on, wrap-around included, and nothing when the loop says
    /// this song goes again — that is the row worth having on the phone already.
    private var nextUp: (any Playable)? {
        guard hasNext, repeatMode != .one else { return nil }
        return queue[index + 1 < queue.count ? index + 1 : 0]
    }

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
        // The star the system draws in its own media controls — the lock screen, Control Centre, the
        // Dynamic Island's Now Playing and the same card as a Live Activity. It is `ratingCommand`:
        // `likeCommand` is the heart, and the star slot only exists once this command is enabled.
        // Doni has no ratings, so one star at the top of the scale means exactly what the row's heart
        // means, and the press toggles it either way.
        center.ratingCommand.minimumRating = 0
        center.ratingCommand.maximumRating = 1
        center.ratingCommand.addTarget { _ in
            Task { @MainActor in self.rateFromRemote() }
            return .success
        }
        center.ratingCommand.isEnabled = true
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
        persist()
    }

    /// The repeat pill walks the three states in the order the reference draws them.
    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        persist()
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
        persist()
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
        prefetch?.cancel()
        prefetch = nil
        prefetchingId = nil
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
        wantsPlayWhenReady = false
        lastPersistedSecond = -1
        PlaybackPersistence.clear()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        engine?.pause()
        isPlaying = false
        publishNowPlaying(elapsed: elapsed)
        persist()
    }

    func resume() {
        // Pressing play on a row that has no engine behind it and no fetch in flight means it: the
        // load is asked for again rather than being a silent no-op. A fetch that is still running
        // needs no second one — TDLib would be told to stop and start over on the same file — but
        // it does need the press remembered, or the play that arrived early is never answered.
        if engine == nil {
            guard current != nil else { return }
            if isFetchingFile { wantsPlayWhenReady = true } else { startCurrent() }
            return
        }
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
        lastPersistedSecond = Int(clamped)
        publishNowPlaying(elapsed: clamped)
        persist()
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

    // MARK: Restarting where the listening left off

    /// Writing the plan down, in the reference's shape (`PlayerStore.swift:1591-1610`).
    ///
    /// An empty player clears the note only once it has actually been running: a volume slider on
    /// the Settings sheet can move before `restore()` has read the snapshot, and clearing then
    /// would throw away the very song the launch was supposed to bring back.
    private func persist() {
        guard !queue.isEmpty else {
            if hasRestoredPlayback { PlaybackPersistence.clear() }
            return
        }
        PlaybackPersistence.save(PlaybackSnapshot(
            queue: queue.map(\.uniqueId),
            source: source.map(\.uniqueId),
            currentIndex: index,
            progress: elapsed,
            isShuffled: isShuffled,
            repeatMode: repeatMode,
            volume: volume
        ))
    }

    /// Reloading the last session — the same rows in the same order, at the second the song had
    /// reached, loaded and left paused (`PlayerStore.swift:276-312`, which ends with
    /// `loadCurrentSong(autoplay: false, startAt: progress)`).
    ///
    /// The snapshot holds `unique_id`s rather than whole songs on purpose: a row re-read from the
    /// store carries the `file_id` that is true *now*, and a song the walk has since deleted drops
    /// out of the restored queue instead of becoming a row that cannot play.
    func restore() {
        guard !hasRestoredPlayback else { return }
        hasRestoredPlayback = true
        guard let snapshot = PlaybackPersistence.load() else { return }
        let tracks = snapshot.queue.compactMap { library.store.track(uniqueId: $0) }
        guard !tracks.isEmpty else {
            PlaybackPersistence.clear()
            return
        }
        // Turning shuffle off goes back to the order the list was opened in, and that is not the
        // order it plays in — so both lists are read back, not just the one under the finger.
        let opened = snapshot.source.compactMap { library.store.track(uniqueId: $0) }
        source = opened.isEmpty ? tracks : opened
        queue = tracks
        // The playhead follows the song it was on rather than the number it was at: rows that left
        // the library shift the index, and the id is the only thing that survives that.
        let held = snapshot.queue.indices.contains(snapshot.currentIndex)
            ? snapshot.queue[snapshot.currentIndex]
            : nil
        index = held.flatMap { left in tracks.firstIndex { $0.uniqueId == left } }
            ?? min(max(snapshot.currentIndex, 0), tracks.count - 1)
        isShuffled = snapshot.isShuffled
        repeatMode = snapshot.repeatMode
        current = tracks[index]
        duration = Double(tracks[index].duration ?? 0)
        elapsed = min(max(snapshot.progress, 0), duration)
        volume = min(max(snapshot.volume, 0), 1)
        lastPersistedSecond = Int(elapsed)
        startCurrent(autoplay: false, startAt: elapsed)
    }

    // MARK: Bringing a song onto the phone

    /// Takes a song the list is showing but the phone does not have yet. Playing it fetches the same
    /// file as a side effect; this is the press that wants the file without wanting the noise, which
    /// is what the Cloud Music tab's swipe is for. It answers when the file is on the device, so the
    /// screen that asked can stop showing its spinner. The downloader coalesces waiters per file, so
    /// a play that arrives mid-download does not start a second copy.
    func download(_ track: any Playable) async {
        guard !track.isDownloaded, let downloader else { return }
        guard let onDisk = await downloader.path(
            fileId: track.fileId, priority: TdFileDownloader.audioPriority
        ) else { return }
        library.recordDownload(path: onDisk, uniqueId: track.uniqueId)
    }

    /// How much of a song has to be left before the one behind it is brought onto the phone.
    ///
    /// Ten seconds is about what a file takes to land on a phone's connection, and asking earlier
    /// would spend the download on songs the listener may never reach.
    private static let prefetchLead: TimeInterval = 10

    /// The lead-time fetch, asked for once per song.
    ///
    /// A quarter-second timer is the only clock the player has, so this is a threshold the tick
    /// crosses rather than an event TDLib sends. `download` is the ask every other surface uses, and
    /// a press that lands mid-fetch is answered by the same file rather than a second copy of it —
    /// which is the whole reason prefetching the next song is safe to start before it is wanted.
    private func prefetchAhead(remaining: TimeInterval) {
        guard isPlaying, remaining <= Self.prefetchLead, let track = nextUp else { return }
        guard !track.isDownloaded, track.uniqueId != prefetchingId else { return }
        prefetchingId = track.uniqueId
        prefetch = Task { await self.download(track) }
    }

    // MARK: Loading

    /// Loading the row under the playhead. `autoplay: false` is the relaunch case: the song is
    /// fetched and wound to `startAt` but left still, because an app that starts making noise by
    /// itself is an app that has just insulted everyone in the room.
    private func startCurrent(autoplay: Bool = true, startAt: TimeInterval? = nil) {
        guard index >= 0, index < queue.count else { return }
        let track = queue[index]
        let held = current?.uniqueId
        // An early play press belonged to the song before this one.
        wantsPlayWhenReady = false
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
        // The row keeps its place when the same song is asked for again — that is the press that
        // retries a fetch — and starts at zero when the queue has moved on.
        elapsed = startAt ?? (held == track.uniqueId ? elapsed : 0)
        duration = Double(track.duration ?? 0)
        isFetchingFile = track.localPath == nil
        lastPersistedSecond = Int(elapsed)
        persist()

        // A lead-time fetch for the song the playhead has just arrived on stays: the seat it holds at
        // TDLib is the one the load below needs anyway. One that has been left behind goes, because
        // it shares the download queue with the song the user actually pressed.
        if let prefetchingId, prefetchingId != track.uniqueId, prefetchingId != nextUp?.uniqueId {
            self.prefetchingId = nil
            prefetch?.cancel()
            prefetch = nil
        }

        let path = track.localPath
        let fileId = track.fileId
        let downloader = self.downloader
        loading = Task {
            // A stored path is a note that the file was once on the phone, not proof it is still
            // there: TDLib empties its own cache when the device runs short, and a one-hour set at
            // a hundred and forty megabytes is the first thing it throws away. The note used to be
            // trusted blindly and the `try?` in `open` answered a missing file with silence — which
            // is what "an hour-long song never plays, it just waits" turns out to be.
            if let path, FileManager.default.fileExists(atPath: path),
               open(path: path, track: track, startAt: startAt, play: autoplay) {
                return
            }
            isFetchingFile = true
            guard !Task.isCancelled, let onDisk = await downloader?.path(
                fileId: fileId, priority: TdFileDownloader.audioPriority
            ), !Task.isCancelled else {
                isFetchingFile = false
                return
            }
            // The path that was asked for is the one written down: a stored path that turned out to
            // be stale is corrected here rather than left to fail again next time.
            library.recordDownload(path: onDisk, uniqueId: track.uniqueId)
            _ = open(path: onDisk, track: track, startAt: startAt, play: autoplay)
        }
    }

    /// Hands the file to `AVAudioPlayer` and starts it. False means the row goes back to its play
    /// glyph instead of spinning — a second chance is the caller's, not this function's.
    @discardableResult
    private func open(path: String, track: any Playable,
                      startAt: TimeInterval? = nil, play: Bool = true) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let engine = try? AVAudioPlayer(contentsOf: url) else {
            isFetchingFile = false
            return false
        }
        self.engine = engine
        engine.delegate = endWatcher
        self.duration = engine.duration
        self.isFetchingFile = false
        // A document post has no duration in the schema and the engine has just read the container's
        // own, so the row that was showing a mime type and a byte count gets the number it should
        // have had. Free here and nowhere else: `AVAudioPlayer` has already opened the file.
        if track.duration == nil, engine.duration > 0.5 {
            library.recordDuration(Int(engine.duration.rounded()), uniqueId: track.uniqueId)
        }
        // A fresh `AVAudioPlayer` starts at full, so the slider's position has to be written into
        // it before the first sample goes out — otherwise the second song of a queue jumps louder.
        engine.volume = volume
        // A restored position wins over a cut: the cut was the last thing the player did to a
        // different song, and a slice does not travel across a launch.
        if let startAt {
            engine.currentTime = min(startAt, engine.duration)
            elapsed = engine.currentTime
        } else if let segment {
            engine.currentTime = segment.lowerBound
            elapsed = segment.lowerBound
        }
        engine.prepareToPlay()
        let wantsEarlyPress = wantsPlayWhenReady
        wantsPlayWhenReady = false
        guard play || wantsEarlyPress else {
            // The relaunch leaves the row wound up and quiet: the clock never starts, so nothing
            // advances the bar until the user presses play.
            isPlaying = false
            publishNowPlaying(elapsed: engine.currentTime, track: track)
            return true
        }
        engine.play()
        isPlaying = true
        startTicker()
        publishNowPlaying(elapsed: engine.currentTime, track: track)
        return true
    }

    /// A timer for the progress bar and for the cut's own boundary; the file's end comes from the
    /// delegate, which is the only thing that actually knows it.
    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let engine else { return }
        let end = segment?.upperBound ?? engine.duration
        prefetchAhead(remaining: end - engine.currentTime)
        // Only a cut is a boundary the timer can watch: nothing stops the file at the slice's end,
        // so the playhead goes on and the next tick is at most a quarter of a second late.
        if let segment, engine.currentTime >= segment.upperBound - 0.05 {
            // A favourited slice loops: that is the point of saving three minutes of a
            // one-hour set.
            engine.currentTime = segment.lowerBound
        }
        elapsed = engine.currentTime
        let second = Int(elapsed)
        if second != lastPersistedSecond {
            lastPersistedSecond = second
            persist()
        }
        if isPlaying { publishNowPlaying(elapsed: engine.currentTime) }
    }

    /// The file ran out, as `AVAudioPlayer` itself reports.
    ///
    /// This used to be the timer's job, and it is why a queue stopped after one song. The tick's test
    /// was `currentTime >= duration - 0.05` — a window of fifty milliseconds — while the tick comes
    /// every two hundred and fifty, and `AVAudioPlayer` rewinds its own `currentTime` to zero the
    /// moment the file ends. Measured over three files out of the library: the playhead reads exactly
    /// `duration` on a tick that happens to land inside the window and `0.00` on every one after it,
    /// so roughly one song in five handed over to the next and the rest left the app playing silence
    /// under a full progress bar. The delegate fires for all three.
    private func songEnded() {
        // A song that was paused, seeked or replaced on the way here has nothing to answer for.
        guard let engine, isPlaying else { return }
        if repeatMode == .one {
            // A player that has finished is not playing any more, so the loop has to ask for sound.
            engine.currentTime = 0
            engine.play()
        } else if hasNext {
            next()
        } else {
            pause()
            engine.currentTime = 0
        }
    }

    // MARK: Lock screen and control centre

    /// The star's answer: the same heart the row wears, pressed from outside the app.
    ///
    /// The rating the event carries is not trusted — some of the system's surfaces send the maximum on
    /// every press rather than the change they want — so a press flips whatever the row would do.
    private func rateFromRemote() {
        guard let track = current else { return }
        library.toggleFavorite(track)
        publishNowPlaying(elapsed: elapsed)
    }

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
        // The system's star is filled from this, and it is the only way the lock screen, Control
        // Centre and the Dynamic Island can tell a favourited song from one that is merely playing.
        // Read off the list the library already publishes rather than from the store: this dictionary
        // is rewritten four times a second by the ticker.
        info[MPMediaItemPropertyRating] =
            library.favorites.contains(where: { $0.track.uniqueId == shown.uniqueId }) ? 1.0 : 0.0
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

/// `AVAudioPlayerDelegate` in its own object, because the protocol's methods are nonisolated and
/// `Player` is not.
///
/// It carries one fact — this file has run out — and nothing else about the audio session: a pause,
/// a seek or a route change is not an ending, and the player has to be able to tell them apart.
/// Sendable because its only property is an immutable `@Sendable` closure.
private final class SongEndWatcher: NSObject, AVAudioPlayerDelegate, Sendable {
    private let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
