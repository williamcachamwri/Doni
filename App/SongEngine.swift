import AVFoundation
import Foundation
import Support
import TdSession
import UIKit

/// What `Player` actually does to the thing making noise, which is both of the two ways a song can
/// reach an ear here.
///
/// `AVAudioPlayer` opens a whole file and is the right tool for a song the phone already has — it
/// seeks exactly, costs nothing to start and has a real `volume`. `AVPlayer` is the right tool for a
/// song that is still arriving, and it needs a different shape underneath. Everything else the player
/// does — the queue, the cut, the clock, the lock screen — is the same on both sides of this protocol,
/// which is the whole reason it exists: `Player` should not have to know which one it is holding.
@MainActor
protocol SongEngine: AnyObject {
    /// The length of what is playing. `0` means the container has not told us yet, which is a
    /// different fact from a song that is a fraction of a second long.
    var duration: TimeInterval { get }
    /// Whether the length is a measurement or a guess. A stream's duration comes from dividing its
    /// byte count by an average bitrate, and that is good enough to draw a progress bar with and not
    /// good enough to write into the library as the song's own length.
    var durationIsExact: Bool { get }
    var currentTime: TimeInterval { get set }
    var volume: Float { get set }
    /// The word that this song ran out. `AVAudioPlayer` reports it through its delegate and
    /// `AVPlayer` posts a notification; both are the file's end, and neither is a pause.
    var onEnd: (@MainActor () -> Void)? { get set }
    /// Whether the engine is consuming time right now. This is the only honest answer to "is the
    /// song playing": a paused player is not, and a player waiting for bytes is not either — which
    /// is what a progress bar that keeps walking across a silent speaker turns out to have been
    /// asking for all along.
    var isProducingSound: Bool { get }
    /// Whether the engine has run dry and is waiting for bytes. Not a failure yet: a second of this
    /// is buffering, a minute of it is a song that is not coming.
    var isWaitingForData: Bool { get }
    /// The transport's own last word about the bytes, for the engine that has a transport. `nil`
    /// means either "nothing has gone wrong" or "this engine reads a file and asked nobody".
    var transportFailure: AudioStreamError? { get }
    func play()
    func pause()
    func stop()
    /// The whole-file engine wants a moment to build its buffers; a stream is already doing that.
    func prime()
}

// MARK: Whole file

/// A song the phone has all of.
///
/// `AVAudioPlayer` is not `Sendable`, so it cannot be built on whichever thread asked for it and
/// handed over — `load` is the one allowed crossing, off the main thread because a one-hour set is a
/// hundred and forty megabytes of file to open and that used to freeze the screen that asked.
@MainActor
final class FileSongEngine: NSObject, SongEngine, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onEnd: (@MainActor () -> Void)?

    private init(player: AVAudioPlayer) {
        self.player = player
        super.init()
    }

    /// The file, opened away from the main actor. `nil` means the file is not there or is not audio.
    static func load(path: String) async -> FileSongEngine? {
        let url = URL(fileURLWithPath: path)
        let handoff = await Task.detached(priority: .userInitiated) {
            FileSongHandoff(player: try? AVAudioPlayer(contentsOf: url))
        }.value
        guard let player = handoff.player else { return nil }
        let engine = FileSongEngine(player: player)
        player.delegate = engine
        return engine
    }

    var duration: TimeInterval { player.duration }
    var durationIsExact: Bool { true }
    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }
    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }
    func prime() { player.prepareToPlay() }

    var isProducingSound: Bool { player.isPlaying }
    var isWaitingForData: Bool { false }
    var transportFailure: AudioStreamError? { nil }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onEnd?()
    }
}

/// `AVAudioPlayer` is not `Sendable`, so it cannot be handed back from a detached task by itself.
/// This box is the one allowed crossing: built off the main thread, arrives on it, and never leaves.
private struct FileSongHandoff: @unchecked Sendable {
    let player: AVAudioPlayer?
}

// MARK: Stream

/// The bytes of one Telegram file, in ranges, as TDLib has them.
///
/// `want` is the interesting part: it is what makes a seek a *seek*. TDLib keeps one download window
/// per file and moves it on the download already running, so asking for the bytes at four minutes is
/// asking the fetch to go to four minutes — not asking for the file again from the start.
nonisolated final class TelegramAudioSource: AudioByteProviding, Sendable {
    private let file: TdFile
    private let downloader: TdFileDownloader

    init(file: TdFile, downloader: TdFileDownloader) {
        self.file = file
        self.downloader = downloader
    }

    func totalBytes() async -> Int64? {
        guard let size = await downloader.state(file)?.size, size > 0 else { return nil }
        return size
    }

    func read(at offset: Int64, count: Int) async -> Data? {
        await downloader.read(file, at: offset, upTo: count)
    }

    func want(_ range: AudioByteRange) async {
        // Only the window is moved here, and no waiting: the player owns when the fetch is left
        // running and when it is stopped, and a second owner that cancelled the file would stop the
        // bytes this one is waiting for.
        _ = await downloader.ask(file, window: range.offset, bytes: range.count)
    }
}

/// A song that is still arriving.
@MainActor
final class StreamSongEngine: NSObject, SongEngine {
    private let player: AVPlayer
    private let item: AVPlayerItem
    private let loader: AudioStreamLoader
    private var endObserver: Task<Void, Never>?
    var onEnd: (@MainActor () -> Void)?

    /// The transport's give-up, delivered on the main actor the moment it happens. A caller that
    /// only learns it on its next poll has already drawn another quarter second of progress bar
    /// across a song that is not playing.
    var onTransportFailure: (@MainActor (AudioStreamError) -> Void)? {
        didSet {
            loader.onFailure = { [weak self] error in
                Task { @MainActor in self?.onTransportFailure?(error) }
            }
        }
    }

    /// The library's own number for this song, which is what Telegram's audio object carries and is
    /// exact. A stream's container duration is a division, so this is preferred when it exists.
    private let storedDuration: TimeInterval

    private init(player: AVPlayer, item: AVPlayerItem, loader: AudioStreamLoader,
                 storedDuration: TimeInterval) {
        self.player = player
        self.item = item
        self.loader = loader
        self.storedDuration = storedDuration
    }

    /// The asset, parsed far enough to know what song it is. `nil` means the head of the file never
    /// came, which is a network answer rather than a broken song, and the caller falls back to
    /// fetching the whole file the way it always did.
    ///
    /// There is no timer here on purpose: loading the tracks waits on the loader, and the loader
    /// gives up on a range after its own share of empty passes. One clock is enough for a stream.
    static func load(source: TelegramAudioSource, key: String, fileType: String,
                     storedDuration: TimeInterval) async -> StreamSongEngine? {
        let url = AudioStreamLoader.url(for: key, fileType: fileType)
        // A shorter patience than a playing stream gets: this is the first parse of a file nobody has
        // asked for yet, and six seconds of nothing on the other side of it is a song that should be
        // fetched the way it always was rather than buffered forever.
        let loader = AudioStreamLoader(source: source, url: url, stallPasses: 100)
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "local.doni.audio.stream"))
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !tracks.isEmpty else {
            loader.stop()
            return nil
        }
        let item = AVPlayerItem(asset: asset)
        let engine = StreamSongEngine(player: AVPlayer(playerItem: item), item: item, loader: loader,
                                      storedDuration: storedDuration)
        engine.watchEnd()
        return engine
    }

    private func watchEnd() {
        let watched = item
        let name = AVPlayerItem.didPlayToEndTimeNotification
        endObserver?.cancel()
        endObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name, object: watched) {
                guard let self, !Task.isCancelled else { return }
                self.onEnd?()
            }
        }
    }

    var duration: TimeInterval {
        let measured = CMTimeGetSeconds(item.duration)
        if measured.isFinite, measured > 0.5 { return measured }
        return storedDuration
    }

    var durationIsExact: Bool { storedDuration > 0 }

    var currentTime: TimeInterval {
        get { CMTimeGetSeconds(player.currentTime()) }
        set {
            // Zero tolerance on both sides: a cut's boundary and a scrub's landing point are the
            // same promise, and AVPlayer's default "anywhere near there" is not that promise.
            player.seek(to: CMTime(seconds: newValue, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    /// `timeControlStatus`, not `rate`: a player that has been told to play and has nothing to play
    /// keeps its rate at 1 and stops moving its own clock, and a bar driven by the rate walks off
    /// across a silent speaker.
    var isProducingSound: Bool { player.timeControlStatus == .playing }
    var isWaitingForData: Bool { player.timeControlStatus == .waitingToPlayAtSpecifiedRate }
    var transportFailure: AudioStreamError? { loader.lastError }

    func stop() {
        endObserver?.cancel()
        endObserver = nil
        loader.stop()
        player.pause()
    }

    func prime() {}
}
