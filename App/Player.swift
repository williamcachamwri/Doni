import AVFoundation
import DoniLyrics
import MediaPlayer
import Support
import SwiftUI
import TelegramDesignSystem
import TdSession
import UIKit

/// The one thing that makes noise, over either of the two ways a song can reach an ear: `AVAudioPlayer`
/// on a whole file the phone already has, where a segment favourite needs a seek that lands exactly, and
/// `AVPlayer` on a resource loader serving byte ranges out of a file still arriving. Background audio
/// needs the `.playback` session plus `UIBackgroundModes` listing `audio`.
@MainActor
final class Player: ObservableObject {
    /// What the end of the queue is: an ending, a loop of the whole list, or a loop of this song.
    /// `String` raw value because the resume snapshot keeps it as text
    /// (`PlaybackQueue.swift:3`, `PlaybackPersistence.swift:7`).
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
    /// than in the panel because the chip and the queue's pill both show the same cut.
    @Published private(set) var markIn: TimeInterval?
    /// The queue as the up-next page shows it, in the order it will be played.
    @Published private(set) var queue: [any Playable] = []
    /// Which row of `queue` is playing, so the page can mark it and a swipe can be answered.
    @Published private(set) var index = 0
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    /// Why a stream stopped without being asked to. `nil` means nothing is wrong, or the user
    /// stopped it themselves — only one of those needs a sentence on the screen.
    @Published private(set) var playbackProblem: PlaybackProblem?
    /// Whether the song is playing but waiting for bytes: the one state that is neither paused
    /// nor broken, and the only one this spinner answers for.
    @Published private(set) var isBuffering = false
    private let network = Network.shared
    /// How long the engine has not been producing sound, counted in ticks.
    private var stalledSeconds: TimeInterval = 0
    /// The player's own volume, 0…1 — `AVAudioPlayer` has a real one, so the bar moves sound.
    @Published var volume: Float = 1 {
        didSet {
            engine?.volume = volume
            publishNowPlaying(elapsed: elapsed)
            persist()
        }
    }

    /// The order the list was played in, kept so turning shuffle off puts it back.
    private var source: [any Playable] = []
    /// The system's media controls, held as a property because the favourite's state is written back
    /// to the command from inside the app: the row's heart and the lock screen's button are one fact.
    private let commands = MPRemoteCommandCenter.shared()
    private var engine: (any SongEngine)?
    private var ticker: Timer?
    /// The song currently streamed rather than played from a whole file, and the one download window
    /// it owns.
    private struct Streaming {
        let file: TdFile
        let size: Int64
        /// Bytes per second, once something knows the length. Recomputed from the container when the
        /// message did not carry one, which is why it is not a `let`.
        var bytesPerSecond: Double
        var policy = AudioWindowPolicy()
        var fetch: Task<Void, Never>?
    }
    private var streaming: Streaming?
    private var loading: Task<Void, Never>?
    /// What the audio session and the app's own life have to say, kept so the singleton holds every
    /// observer for its whole life.
    private var sessionObservers: [Task<Void, Never>] = []
    /// Whether sound was going when something else took the session. Only that question decides
    /// whether to give it back: a pause the user pressed themselves is not a pause to undo.
    private var wantsResumeAfterInterruption = false
    /// The lead-time fetch of the song queued behind this one, and the song it was started for; the
    /// id stops the quarter-second tick re-asking for the same file.
    private var prefetch: Task<Void, Never>?
    private var prefetchingId: String?
    /// The second last written into the resume snapshot, so the clock saves once per second of
    /// listening and not four times (`PlayerStore.swift:190, 1231-1235`).
    private var lastPersistedSecond = -1
    /// `restore()` runs once per launch, however many views ask for it
    /// (`PlayerStore.swift:184, 277-278`).
    private var hasRestoredPlayback = false
    /// A play press that arrived while the file was still being fetched; the load honours it when it
    /// lands.
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
        // Background audio survives only with the `.playback` category set before the first file is
        // opened; `UIBackgroundModes` lists `audio` for the same reason.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let center = commands
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
        // The system's own favourite button: `likeCommand`, one of the three feedback commands
        // (`MPRemoteCommandCenter.h:54-58`), and the only one whose glyph the system also fills in —
        // `isActive` means "the user already liked this item", so one control carries both states.
        center.likeCommand.localizedTitle = "Thêm vào yêu thích"
        center.likeCommand.localizedShortTitle = "Yêu thích"
        center.likeCommand.addTarget { _ in
            Task { @MainActor in self.likeFromRemote() }
            return .success
        }
        center.likeCommand.isEnabled = true
        // Held as properties rather than locals because an `AsyncStream` of notifications dies with
        // whoever is reading it.
        sessionObservers = [
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(
                    named: AVAudioSession.interruptionNotification
                ) {
                    self?.handleInterruption(note.userInfo)
                }
            },
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(
                    named: AVAudioSession.routeChangeNotification
                ) {
                    self?.handleRouteChange(note.userInfo)
                }
            },
            // Background audio keeps the sound going but not the run loop servicing timers, so the
            // clock stops mid-song; re-arming on every return is what makes the tick honest again.
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: UIApplication.didBecomeActiveNotification
                ) {
                    self?.rewarmTicker()
                }
            },
            // The connection coming back is the one event that makes a stopped stream worth another
            // look: the window has to be asked for again before the play button means anything.
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.network.$isOnline.values {
                    self.rearmAfterNetwork()
                }
            },
        ]
        network.start()
    }

    /// Something else took the audio session: a call, Siri, an alarm, another app's sound.
    ///
    /// `AVAudioPlayer` stops on its own and says nothing to the app, so the play glyph, the lock
    /// screen's clock and the saved position would all keep advancing over silence.
    private func handleInterruption(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            guard isPlaying else { return }
            wantsResumeAfterInterruption = true
            pause()
            return
        }
        guard type == .ended, wantsResumeAfterInterruption else { return }
        wantsResumeAfterInterruption = false
        // The system's flag, not TDLib's answer, says whether this app may take the session back: a
        // call that moved to another device ends with `.shouldResume` clear.
        let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt)
            .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
        guard options.contains(.shouldResume) else { return }
        resume()
    }

    /// The output the song was going to has gone away — AirPods taken out, headphones unplugged.
    ///
    /// A `.playback` session silently moves to the built-in speaker, so only the *old* device going
    /// is a reason to stop; a new one arriving (CarPlay, a speaker) is a reason to carry on.
    private func handleRouteChange(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable,
              isPlaying
        else { return }
        pause()
    }

    /// Plays one track out of `list`, fetching its file first if the phone does not have it. The
    /// whole list becomes the queue, so next/previous walk the channel newest first.
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
        set(order: target, pinAsSource: true)
    }

    /// Dragging a row somewhere else. A hand-made order is the user's, so it also becomes the order
    /// a shuffle-off goes back to.
    func move(from offsets: IndexSet, to destination: Int) {
        guard !offsets.isEmpty else { return }
        var target = queue
        target.move(fromOffsets: offsets, toOffset: destination)
        set(order: target, pinAsSource: true)
    }

    /// Taking rows out of the queue. The song that is playing keeps playing: the queue is a plan for
    /// what comes next, not the thing making noise.
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
        wantsResumeAfterInterruption = false
        PlaybackPersistence.clear()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // The engine went above, so this is when the session can be handed back: holding it after
        // silence keeps every other app on the phone mute until this one is killed.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        engine?.pause()
        isPlaying = false
        isBuffering = false
        ticker?.invalidate()
        ticker = nil
        publishNowPlaying(elapsed: elapsed)
        persist()
    }

    func resume() {
        // Play with no engine and no fetch in flight means the load: ask again rather than be a
        // silent no-op. A fetch already running must not be restarted — TDLib would cancel and
        // re-open the same file — so only the press is remembered.
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
        isBuffering = false
        // A play press is the listener saying the reason does not matter: the sentence goes, and the
        // stall count restarts on a fresh attempt.
        playbackProblem = nil
        stalledSeconds = 0
        isPlaying = true
        startTicker()
        publishNowPlaying(elapsed: elapsed)
    }

    /// The one action a stopped stream answers: start the same song again from where it stopped.
    ///
    /// Not `resume()` — a failed load takes its `AVPlayerItem` down with it, and play on a dead item
    /// is silence. A new load is a new asset and a new ask for the same bytes.
    func retry() {
        playbackProblem = nil
        stalledSeconds = 0
        streaming?.policy.forgetAsked()
        startCurrent(autoplay: true, startAt: elapsed)
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
        // More than three seconds in, the press goes back to this song's own start; the next one leaves.
        if elapsed > 3 {
            seek(to: 0)
            return
        }
        index = index > 0 ? index - 1 : queue.count - 1
        startCurrent()
    }

    func seek(to seconds: TimeInterval) {
        // No engine is not a song at zero. The bar is live while a file is still arriving, and writing
        // a clamped 0 here would persist the rewind the drag was meant to undo.
        guard let engine else { return }
        let floor = segment?.lowerBound ?? 0
        let ceiling = segment?.upperBound ?? engine.duration
        let clamped = min(max(seconds, floor), ceiling)
        engine.currentTime = clamped
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
    /// An empty player clears the note only once `restore()` has run, because a volume slider can
    /// move before it does and clear the snapshot the launch was meant to read.
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

    /// Reloading the last session: the same rows in the same order, at the second the song had
    /// reached, loaded and left paused (`PlayerStore.swift:276-312`, ending with
    /// `loadCurrentSong(autoplay: false, startAt: progress)`).
    ///
    /// The snapshot holds `unique_id`s, not whole songs: a row re-read from the store carries the
    /// `file_id` that is true now, and a song the walk deleted drops out instead of becoming an
    /// unplayable row.
    func restore() {
        guard !hasRestoredPlayback else { return }
        hasRestoredPlayback = true
        guard let snapshot = PlaybackPersistence.load() else { return }
        let tracks = snapshot.queue.compactMap { library.store.track(uniqueId: $0) }
        guard !tracks.isEmpty else {
            PlaybackPersistence.clear()
            return
        }
        // Turning shuffle off goes back to the order the list was opened in, which is not the order
        // it plays in, so both lists are read back.
        let opened = snapshot.source.compactMap { library.store.track(uniqueId: $0) }
        source = opened.isEmpty ? tracks : opened
        queue = tracks
        // The playhead follows the song it was on, not the number it was at: rows that left the
        // library shift the index, and only the id survives that.
        let held = snapshot.queue.indices.contains(snapshot.currentIndex)
            ? snapshot.queue[snapshot.currentIndex]
            : nil
        index = held.flatMap { left in tracks.firstIndex { $0.uniqueId == left } }
            ?? min(max(snapshot.currentIndex, 0), tracks.count - 1)
        isShuffled = snapshot.isShuffled
        repeatMode = snapshot.repeatMode
        current = tracks[index]
        duration = Double(tracks[index].duration ?? 0)
        // A length the app has never measured is unknown, not zero — and a zero here would clamp every
        // stored position down to the start of the song. Document posts carry no duration in the schema,
        // so this is the common case rather than the odd one.
        elapsed = duration > 0 ? min(max(snapshot.progress, 0), duration) : max(snapshot.progress, 0)
        volume = min(max(snapshot.volume, 0), 1)
        lastPersistedSecond = Int(elapsed)
        startCurrent(autoplay: false, startAt: elapsed)
    }

    // MARK: Bringing a song onto the phone

    /// Takes a song the list shows but the phone does not have yet: the press that wants the file
    /// without the noise. Answers when the file is on the device. The downloader coalesces waiters
    /// per file, so a play arriving mid-download does not start a second copy.
    func download(_ track: any Playable) async {
        guard !track.isDownloaded, let downloader else { return }
        guard let onDisk = await downloader.path(
            TdFile(audio: track), priority: TdFileDownloader.audioPriority
        ) else { return }
        library.recordDownload(path: onDisk, uniqueId: track.uniqueId)
    }

    /// How much of a song has to be left before the one behind it is fetched: ten seconds is about
    /// what a file takes to land, and asking earlier spends downloads on songs never reached.
    private static let prefetchLead: TimeInterval = 10

    /// The lead-time fetch, asked for once per song: a threshold the quarter-second tick crosses, not
    /// an event TDLib sends. A press landing mid-fetch is answered by the same file, which is what
    /// makes prefetching before a song is wanted safe.
    ///
    /// A streamable song only gets its head, at cover priority: the lead time exists so the next song
    /// starts instantly, not so the queue pulls a file the listener may never reach.
    private func prefetchAhead(remaining: TimeInterval) {
        guard isPlaying, remaining <= Self.prefetchLead, let track = nextUp else { return }
        guard !track.isDownloaded, track.uniqueId != prefetchingId else { return }
        prefetchingId = track.uniqueId
        prefetch = Task { await self.prepare(track) }
    }

    /// The head of the next song, or the whole of it when the container cannot be streamed.
    ///
    /// Bounded: a prefetch that keeps downloading is a second song eating the link the first one is
    /// playing on, and TDLib only stops when it is told to (`fetch`'s note).
    ///
    /// The size is asked of TDLib rather than read off the row: a document post often carries none, and
    /// a prefetch that mistook "the message does not say" for "there is nothing to stream" pulled the
    /// whole file ten seconds before the playhead ever arrived — which is a download manager, not a
    /// prefetch.
    private func prepare(_ track: any Playable) async {
        guard let downloader else { return }
        let file = TdFile(audio: track)
        guard AudioContentType.resolve(mimeType: track.mimeType, fileName: track.fileName) != nil,
              let size = track.size > 0 ? track.size : await downloader.state(file)?.size,
              size > 0 else {
            await download(track)
            return
        }
        for window in AudioWindowPolicy.head(for: size, includingTail: keepsTail(track)) {
            _ = await downloader.fetch(file, window: window.offset, bytes: window.count,
                                       priority: TdFileDownloader.coverPriority)
        }
        await downloader.quiet(file)
    }

    /// MP4-family containers put their table of contents at the end of the file, so a head-only read
    /// cannot find the track length; everything else is self-describing from its first frame.
    private func keepsTail(_ track: any Playable) -> Bool {
        guard let ext = AudioContentType.resolve(mimeType: track.mimeType,
                                                 fileName: track.fileName)?.ext else { return false }
        return ["m4a", "mp4", "aac", "m4b"].contains(ext)
    }

    // MARK: Loading

    /// Loading the row under the playhead. `autoplay: false` is the relaunch case: the song is
    /// fetched and wound to `startAt` but left still, so the app never starts making noise by itself.
    private func startCurrent(autoplay: Bool = true, startAt: TimeInterval? = nil) {
        guard index >= 0, index < queue.count else { return }
        let track = queue[index]
        let held = current?.uniqueId
        // An early play press belonged to the song before this one.
        wantsPlayWhenReady = false
        loading?.cancel()
        // The song before this one is put down now, not when the next arrives: `AVAudioPlayer` holds
        // its file open, a one-hour mix is ~140 MB, and the fetch below can take a minute.
        engine?.stop()
        engine = nil
        // A cut is a decision about one song, so it does not travel to the next one.
        segment = nil
        markIn = nil
        current = track
        // Restoring a position is not listening to anything, and this number drives both the "Gần đây
        // phát" shelf and the eviction order — a cold start must not promote a song nobody played.
        if autoplay { library.recordPlay(track) }
        // The words are asked for here rather than by the lyrics panel: the lock screen and the
        // Dynamic Island sing the current line even when the panel never opens. `load` is keyed by
        // the song and keeps its own cache, so a panel opening later costs nothing.
        Lyrics.shared.load(track)
        // The row keeps its place when the same song is asked for again — that is the press that
        // retries a fetch — and starts at zero when the queue has moved on.
        elapsed = startAt ?? (held == track.uniqueId ? elapsed : 0)
        duration = Double(track.duration ?? 0)
        isFetchingFile = track.localPath == nil
        // A new song is a new question: the last one's reason for stopping says nothing about this.
        playbackProblem = nil
        stalledSeconds = 0
        lastPersistedSecond = Int(elapsed)
        persist()

        // A lead-time fetch for the song the playhead has just arrived on stays: it holds the TDLib
        // seat the load below needs anyway. One left behind goes, since it shares the download queue
        // with the song the user actually pressed.
        if let prefetchingId, prefetchingId != track.uniqueId, prefetchingId != nextUp?.uniqueId {
            self.prefetchingId = nil
            prefetch?.cancel()
            prefetch = nil
        }

        let path = track.localPath
        let file = TdFile(audio: track)
        let downloader = self.downloader
        // The song left behind is put down, not finished off: TDLib keeps its bytes either way, and
        // the rest of a mix is exactly the bandwidth the current song is asking for.
        streaming?.fetch?.cancel()
        streaming = nil
        loading = Task {
            // A stored path is a note that the file was once here, not proof it still is: TDLib
            // empties its own cache when the device runs short, and the biggest files go first.
            if let path, FileManager.default.fileExists(atPath: path),
               await open(path: path, track: track, startAt: startAt, play: autoplay) {
                return
            }
            isFetchingFile = true
            // Otherwise the song is played from what is arriving rather than from what has arrived.
            if await stream(track, file: file, startAt: startAt, play: autoplay) { return }
            guard !Task.isCancelled, let onDisk = await downloader?.path(
                file, priority: TdFileDownloader.audioPriority
            ), !Task.isCancelled else {
                isFetchingFile = false
                return
            }
            // The path actually answered is written down, so a stale stored path is corrected here
            // rather than failing again next time.
            library.recordDownload(path: onDisk, uniqueId: track.uniqueId)
            _ = await open(path: onDisk, track: track, startAt: startAt, play: autoplay)
        }
    }

    /// Playing a song out of its bytes as they land. `false` is not a failure: it means the caller
    /// falls back to fetching the whole file. Each way out says why in the log, because a silent
    /// `false` is how two of these guards spent months looking like a network problem.
    ///
    /// The size comes from `getFile`, not from the message attribute: a document post often carries
    /// neither `size` nor `expected_size` until TDLib has looked, and TDLib always knows — a guard on
    /// the message's number pushed streamable files onto the whole-file path for no other reason.
    private func stream(_ track: any Playable, file: TdFile,
                        startAt: TimeInterval?, play: Bool) async -> Bool {
        guard let downloader, !Task.isCancelled else { return false }
        guard let kind = AudioContentType.resolve(mimeType: track.mimeType,
                                                  fileName: track.fileName) else {
            print("stream skip \(track.fileName): AVFoundation cannot decode it")
            return false
        }
        guard let state = await downloader.state(file), state.size > 0 else {
            print("stream skip \(track.fileName): TDLib has no size for the file yet")
            return false
        }
        guard !state.isComplete else {
            print("stream skip \(track.fileName): the whole file is already on the phone")
            return false
        }
        let seconds = Double(track.duration ?? 0)
        // The window plan needs a bitrate to turn the playhead into a byte; until the container is
        // read, the loader's own asks are the only steering there is. A missing `track.duration` is
        // not a reason to stop streaming — see `steerWindow`, which recomputes it from the container.
        let source = TelegramAudioSource(file: file, downloader: downloader)
        for window in AudioWindowPolicy.head(for: state.size, includingTail: keepsTail(track)) {
            _ = await downloader.ask(file, window: window.offset, bytes: window.count)
        }
        print("stream \(track.fileName) size=\(state.size) as=\(kind.ext) mime=\(track.mimeType)")
        let engine = StreamSongEngine.make(source: source, key: track.uniqueId,
                                           fileType: kind.ext, storedDuration: seconds)
        guard !Task.isCancelled else {
            engine.stop()
            return false
        }
        streaming = Streaming(file: file, size: state.size,
                              bytesPerSecond: seconds > 0 ? Double(state.size) / seconds : 0)
        // `.unavailable` is the only answer that means the bytes are not coming: then, and only then,
        // fall back to the whole file. A slow head is not that answer — a slow head is a spinner.
        engine.onTransportFailure = { [weak self] failure in
            guard failure == .unavailable else { return }
            print("stream unavailable \(track.fileName), fetching the file instead")
            self?.fetchWhole(track, file: file, startAt: startAt, play: play)
        }
        install(engine, for: track, startAt: startAt, play: play)
        return true
    }

    /// The whole file, for a song the transport says is not obtainable in pieces.
    private func fetchWhole(_ track: any Playable, file: TdFile,
                            startAt: TimeInterval?, play: Bool) {
        guard let downloader else { return }
        Task { [weak self] in
            guard let onDisk = await downloader.path(
                file, priority: TdFileDownloader.audioPriority
            ) else {
                await MainActor.run { self?.isFetchingFile = false }
                return
            }
            // This Task is nobody's `loading`, so nothing cancels it when the queue moves on. Without
            // the identity check the old song finishes downloading and installs itself: the screen, the
            // strip and the lock screen would name song B while song A came out of the speaker.
            guard let self, self.current?.uniqueId == track.uniqueId else { return }
            self.library.recordDownload(path: onDisk, uniqueId: track.uniqueId)
            _ = await self.open(path: onDisk, track: track, startAt: startAt, play: play)
        }
    }

    /// Moving the one download window to where the sound has got to, and fetching exactly that much.
    ///
    /// One fetch at a time: TDLib keeps a single window per file id, so two tasks asking for two
    /// windows is one task re-offsetting and a second that never finishes. When the window lands the
    /// file is put back to `quiet`, or TDLib keeps pulling the rest of a 160 MB set on the same link
    /// (`fetch`'s note has the measurement).
    private func steerWindow(to seconds: TimeInterval) {
        guard var streaming, let downloader else { return }
        // A document post carries no length, so the map built at start can be empty — and with it
        // zero the window never moves again, which strands the song at its head. The container's own
        // duration is the same number measured from bytes that have already landed: an mp4's `moov`
        // arrives in the tail ask, a wav's header in the first forty-four bytes of the head.
        if streaming.bytesPerSecond <= 0, let engine, engine.duration > 0.5 {
            streaming.bytesPerSecond = Double(streaming.size) / engine.duration
            self.streaming = streaming
            print("window bitrate from the container: \(Int(engine.duration))s")
        }
        guard streaming.bytesPerSecond > 0 else { return }
        guard let plan = streaming.policy.window(atSeconds: seconds,
                                                 bytesPerSecond: streaming.bytesPerSecond,
                                                 fileBytes: streaming.size) else { return }
        streaming.fetch?.cancel()
        let file = streaming.file
        print("window \(plan.offset)+\(plan.count) at \(Int(seconds))s")
        streaming.fetch = Task { [weak self] in
            let ready = await downloader.fetch(file, window: plan.offset, bytes: plan.count)
            await downloader.quiet(file)
            guard let self, !Task.isCancelled else { return }
            // A window that came up short is the buffer running out ahead of the sound: buy further.
            // One that landed whole with double its own cover is the only moment worth buying less.
            if ready < plan.count { self.streaming?.policy.noteRebuffer() }
            else { self.streaming?.policy.noteComfortable(aheadBytes: ready * 2) }
        }
        self.streaming = streaming
    }

    /// Hands the file to the whole-file engine and starts it. False means the row goes back to its
    /// play glyph instead of spinning — a second chance is the caller's, not this function's.
    @discardableResult
    private func open(path: String, track: any Playable,
                      startAt: TimeInterval? = nil, play: Bool = true) async -> Bool {
        // Opening a container reads the file — up to ~140 MB for the hour-long sets these channels
        // post — so it happens off the main thread.
        guard let engine = await FileSongEngine.load(path: path) else {
            // The file is not there or will not open: forgetting the note puts the row back to "not
            // downloaded" so the next tap fetches it instead of failing on the same path forever.
            library.forgetLocalPath(uniqueId: track.uniqueId)
            isFetchingFile = false
            return false
        }
        install(engine, for: track, startAt: startAt, play: play)
        // A document post has no duration in the schema, so the container's own length is recorded
        // here. Only a whole file's length is a measurement worth writing down.
        if track.duration == nil, engine.durationIsExact, engine.duration > 0.5 {
            library.recordDuration(Int(engine.duration.rounded()), uniqueId: track.uniqueId)
        }
        return true
    }

    /// Puts an engine under the playhead: the end word wired up, the volume written in before the
    /// first sample goes out, and the restored position or the saved cut applied.
    private func install(_ engine: any SongEngine, for track: any Playable,
                         startAt: TimeInterval?, play: Bool) {
        engine.onEnd = { [weak self] in self?.songEnded() }
        self.engine = engine
        // One line per song, so a memory-hungry queue is visible in the log.
        MemoryWatch.note("start", track: track.displayTitle)
        duration = engine.duration
        isFetchingFile = false
        // A fresh engine starts at full, so the slider's position goes in before the first sample or
        // the second song of a queue jumps louder.
        engine.volume = volume
        // A restored position wins over a cut: a slice does not travel across a launch.
        if let startAt {
            engine.currentTime = min(startAt, engine.duration)
            elapsed = engine.currentTime
        } else if let segment {
            engine.currentTime = segment.lowerBound
            elapsed = segment.lowerBound
        }
        engine.prime()
        let wantsEarlyPress = wantsPlayWhenReady
        wantsPlayWhenReady = false
        guard play || wantsEarlyPress else {
            // The relaunch leaves the row wound up and quiet: nothing advances the bar until the user
            // presses play.
            isPlaying = false
            publishNowPlaying(elapsed: engine.currentTime, track: track)
            return
        }
        engine.play()
        isPlaying = true
        startTicker()
        publishNowPlaying(elapsed: engine.currentTime, track: track)
    }

    /// A timer for the progress bar and for the cut's own boundary; the file's end comes from the
    /// delegate, which is the only thing that actually knows it.
    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // `.common`, not the `.default` mode `scheduledTimer` picks: a scroll view runs the loop in
        // its tracking mode while a finger is down, so in `.default` the clock stops for the length
        // of every flick — and the cut's loop boundary, which is this timer's job, overshoots.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Re-arming the clock after a background spell: the sound never stopped, so the timer has to be
    /// told where the song actually got to.
    private func rewarmTicker() {
        guard isPlaying, let engine else { return }
        // Set the real position before the first new tick, so a return from ten minutes in the
        // background is one jump rather than a freeze.
        elapsed = engine.currentTime
        startTicker()
    }

    private func tick() {
        guard let engine else { return }
        let end = segment?.upperBound ?? engine.duration
        prefetchAhead(remaining: end - engine.currentTime)
        // Only a cut is a boundary the timer can watch: nothing stops the file at the slice's end,
        // so the playhead goes on and the next tick is at most a quarter of a second late.
        if let segment, engine.currentTime >= segment.upperBound - 0.05 {
            // A favourited slice loops; that is the point of saving one.
            engine.currentTime = segment.lowerBound
        }
        // The clock advances only when the engine is producing sound: a stream that has run dry keeps
        // its rate at 1 and its position still, which is the false "still playing" this guards.
        if engine.isProducingSound { elapsed = engine.currentTime }
        watchStall(engine)
        // A song waiting for bytes is neither paused nor playing, and the row and the transport
        // button have to say the same thing.
        let buffering = isPlaying && engine.isWaitingForData
        if buffering != isBuffering { isBuffering = buffering }
        // A stream is still "fetching" until the container has been read; a whole file never is.
        if streaming != nil { isFetchingFile = !engine.isReadyToPlay }
        steerWindow(to: elapsed)
        let second = Int(elapsed)
        if second != lastPersistedSecond {
            lastPersistedSecond = second
            persist()
        }
        if isPlaying { publishNowPlaying(elapsed: engine.currentTime) }
    }

    /// Why the sound stopped: no path out (`offline`), the path is there and Telegram is not sending
    /// (`stalled`), or Telegram says these bytes are not coming any more (`gone`).
    enum PlaybackProblem: Equatable {
        case offline, stalled, gone
    }

    /// How long a stream may sit still before it is called a problem: 30s while a working connection
    /// buffers, 3s when the bytes cannot arrive at all — no network, or a transport that has said so.
    private static let bufferingPatience: TimeInterval = 30
    private static let hopelessPatience: TimeInterval = 3

    private func watchStall(_ engine: any SongEngine) {
        guard isPlaying, !engine.isProducingSound else {
            stalledSeconds = 0
            return
        }
        stalledSeconds += 0.25
        let failure = engine.transportFailure
        let hopeless = failure != nil || !network.isOnline
        guard stalledSeconds >= (hopeless ? Self.hopelessPatience : Self.bufferingPatience)
        else { return }
        playbackProblem = failure == .unavailable ? .gone
            : (network.isOnline ? .stalled : .offline)
        print("stall \(Int(stalledSeconds))s at \(Int(elapsed))s problem=\(playbackProblem!)")
        // `pause()` is the one door that also clears the clock, the lock screen's rate and the glyph.
        pause()
    }

    /// The bytes are possible again, so the stated reason is no longer true. The song stays paused —
    /// it must never start by itself — but the window is asked for again so play is a resume, not a
    /// wait.
    private func rearmAfterNetwork() {
        guard let problem = playbackProblem, network.isOnline, problem == .offline else { return }
        playbackProblem = nil
        steerWindow(to: elapsed)
    }

    /// Give the cache back to the quota once a song has ended and nothing is being fetched.
    ///
    /// Not while a song is starting: the sweep asks TDLib to throw files away, and a fetch competing
    /// with an eviction is a song that waits longer for its first byte.
    private func trimCache() {
        guard let files = downloader else { return }
        let keeping = current?.uniqueId
        Task { [weak self] in
            let freed = await self?.library.trimCache(with: files, keeping: keeping) ?? 0
            if freed > 0 { MemoryWatch.note("after evicting \(freed)") }
        }
    }

    /// The file ran out, as `AVAudioPlayer` itself reports rather than the timer: a
    /// `duration - 0.05` test is a 50 ms window against a 250 ms tick, and the player rewinds
    /// `currentTime` to 0 at the end, so only about 1 song in 5 handed over. The delegate fires for
    /// all of them.
    private func songEnded() {
        // A song that was paused, seeked or replaced on the way here has nothing to answer for.
        guard let engine, isPlaying else { return }
        if repeatMode == .one {
            // A finished player is not playing, so the loop has to ask for sound again.
            engine.currentTime = 0
            engine.play()
        } else if hasNext {
            next()
        } else {
            pause()
            engine.currentTime = 0
        }
        // The queue moved, so the song before it is now evictable.
        trimCache()
    }

    // MARK: Lock screen and control centre

    /// The favourite, pressed from outside the app: the same heart the row wears.
    ///
    /// Treated as a toggle rather than the state the event carries, because the system sends its own
    /// "liked" for every press.
    private func likeFromRemote() {
        guard let track = current else { return }
        library.toggleFavorite(track)
        publishNowPlaying(elapsed: elapsed)
    }

    private func publishNowPlaying(elapsed: TimeInterval, track: (any Playable)? = nil) {
        let shown = track ?? current
        guard let shown else { return }
        var info: [String: Any] = [
            // The line being sung goes in the title slot — MeloX's default now-playing title is the
            // lyric token (`AppSettings.swift:18`). With no words available the song keeps its name.
            MPMediaItemPropertyTitle: sungLine(for: shown, at: elapsed) ?? shown.displayTitle,
            MPMediaItemPropertyArtist: Self.byline(title: shown.displayTitle,
                                                   artist: shown.displayPerformer),
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            // The lock screen runs its own clock from this rate, so 0 is what holds it still.
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let artwork = artwork(for: shown) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        // The favourite's state lives on the command, not in the dictionary: `isActive` is what makes
        // the system's button read as already liked. This is the one place every change is already
        // reported, and the ticker comes through four times a second, so it is only written when the
        // answer actually moved — read from the list the library publishes, not from the store.
        let on = library.favorites.contains(where: { $0.track.uniqueId == shown.uniqueId })
        if commands.likeCommand.isActive != on { commands.likeCommand.isActive = on }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The line the song is on right now, in the words the lyrics screen is highlighting. `nil` means
    /// the words are not known — no answer yet, none for this song, or before the first line — and
    /// the caller shows the song's name instead.
    ///
    /// Asked of `Lyrics.shared`: the lookup, the cache and the sources are that object's job.
    private func sungLine(for track: any Playable, at seconds: TimeInterval) -> String? {
        let lyrics = Lyrics.shared
        guard lyrics.key == track.uniqueId, !lyrics.lines.isEmpty else { return nil }
        guard let line = LyricLineTimeline.line(at: seconds, in: lyrics.lines,
                                                settings: Lyrics.settings),
              !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return line.text
    }

    /// The artist slot carries "title · artist" (`ui.lyrics.format.default.title_artist`,
    /// `"%@ · %@"`), because the title above is often a lyric and the song's name still has to be
    /// reachable from the lock screen.
    private static func byline(title: String, artist: String) -> String {
        artist.isEmpty ? title : "\(title) · \(artist)"
    }

    /// The lock screen's cover, rebuilt only when the picture actually changed: `nowPlayingInfo`
    /// crosses processes and the ticker writes it four times a second, which uncached made ~14 000
    /// fresh `MPMediaItemArtwork` objects holding copies of one bitmap per hour, until the system
    /// killed the app.
    ///
    /// Hero size is the biggest the lock screen can draw; the row's minithumbnail is the fallback.
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

    /// `MPMediaItemArtwork`'s handler must be `nonisolated`: MediaPlayer calls it from its own queue
    /// (`_onQueue_pushNowPlayingInfoAndRetry:` → `jpegDataWithSize:`), so a closure carrying
    /// `@MainActor` trips `dispatch_assert_queue` and the process dies of a `SIGTRAP`. Only songs
    /// with an artwork can hit it.
    private nonisolated static func mediaArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
