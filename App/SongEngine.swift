import AVFoundation
import Foundation
import Support
import TdSession
import UIKit

/// What `Player` actually does to the thing making noise, which is both of the two ways a song can reach
/// an ear here. `AVAudioPlayer` opens a whole file — exact seeks, cheap start, a real `volume`; `AVPlayer`
/// handles a song still arriving and needs a different shape underneath. Everything else (queue, cut,
/// clock, lock screen) is the same on both sides, so `Player` never has to know which it holds.
@MainActor
protocol SongEngine: AnyObject {
    /// Length of what is playing; `0` means the container has not told us yet — a different fact from a
    /// song a fraction of a second long.
    var duration: TimeInterval { get }
    /// Whether the length is a measurement or a guess: a stream's comes from bytes ÷ average bitrate —
    /// good enough to draw a progress bar, not to write into the library as the song's length.
    var durationIsExact: Bool { get }
    var currentTime: TimeInterval { get set }
    var volume: Float { get set }
    /// The word that this song ran out: `AVAudioPlayer` via its delegate, `AVPlayer` via a notification —
    /// both the file's end, neither a pause.
    var onEnd: (@MainActor () -> Void)? { get set }
    /// Whether the engine is consuming time right now — the only honest answer to "is the song playing":
    /// neither a paused player nor one waiting for bytes is.
    var isProducingSound: Bool { get }
    /// Whether the engine has run dry and is waiting for bytes. Not a failure yet: a second of this is
    /// buffering, a minute of it is a song that is not coming.
    var isWaitingForData: Bool { get }
    /// The transport's last word about the bytes, where there is a transport; `nil` means nothing went
    /// wrong or this engine reads a file and asked nobody.
    var transportFailure: AudioStreamError? { get }
    /// Whether the engine could start making sound if told to. A stream is not ready until the container
    /// is parsed, and the screen must say "still getting it" rather than show a pause button over silence.
    var isReadyToPlay: Bool { get }
    func play()
    func pause()
    func stop()
    /// The whole-file engine wants a moment to build its buffers; a stream is already doing that.
    func prime()
}

// MARK: Whole file

/// A song the phone has all of. `AVAudioPlayer` is not `Sendable`, so it cannot be built on whichever
/// thread asked for it: `load` is the one allowed crossing, off the main thread because a one-hour set is
/// 140 MB of file to open.
@MainActor
final class FileSongEngine: NSObject, SongEngine, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onEnd: (@MainActor () -> Void)?

    private init(player: AVAudioPlayer) {
        self.player = player
        super.init()
    }

    /// The file, opened away from the main actor; `nil` means it is not there or is not audio.
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
    var isReadyToPlay: Bool { true }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onEnd?()
    }
}

/// The one allowed crossing for the non-`Sendable` `AVAudioPlayer`: built off the main thread, arrives on
/// it, and never leaves.
private struct FileSongHandoff: @unchecked Sendable {
    let player: AVAudioPlayer?
}

// MARK: Stream

/// The bytes of one Telegram file, in ranges, as TDLib has them.
/// `want` is what makes a seek a *seek*: TDLib keeps one download window per file and moves it on the
/// download already running, so asking for the bytes at four minutes sends the fetch there rather than
/// starting the file again.
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
        // Only the window moves here, and nothing waits: the player owns when the fetch is left running
        // and when it is stopped, and a second owner cancelling the file would stop these bytes too.
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

    /// The transport's give-up, delivered on the main actor the moment it happens: a caller that only
    /// learns it on its next poll has drawn another quarter second of progress bar over silence.
    var onTransportFailure: (@MainActor (AudioStreamError) -> Void)? {
        didSet {
            loader.onFailure = { [weak self] error in
                Task { @MainActor in self?.onTransportFailure?(error) }
            }
        }
    }

    /// The library's own number for this song — what Telegram's audio object carries, and exact. A
    /// stream's container duration is a division, so this is preferred when it exists.
    private let storedDuration: TimeInterval

    private init(player: AVPlayer, item: AVPlayerItem, loader: AudioStreamLoader,
                 storedDuration: TimeInterval) {
        self.player = player
        self.item = item
        self.loader = loader
        self.storedDuration = storedDuration
    }

    /// The stream, built but not yet parsed. Nothing here waits for the head of the file, and that is the
    /// whole point of this function's shape: the first version loaded the tracks before handing the engine
    /// back, and on a phone's connection a megabyte of head takes longer than any patience that can
    /// honestly be promised — every song on a slow link timed its own streaming out after six seconds and
    /// fell back to downloading the whole file. AVFoundation parses as the bytes land; `isReadyToPlay` is
    /// what the spinner is made of, and the only give-up is the transport saying the bytes are not coming.
    static func make(source: TelegramAudioSource, key: String, fileType: String,
                     storedDuration: TimeInterval) -> StreamSongEngine {
        let url = AudioStreamLoader.url(for: key, fileType: fileType)
        let loader = AudioStreamLoader(source: source, url: url)
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "local.doni.audio.stream"))
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

    /// Not ready until AVFoundation has read enough of the file to know what it is — which on a
    /// stream is a few hundred kilobytes after the ask, not an instant.
    var isReadyToPlay: Bool { item.status == .readyToPlay }

    func stop() {
        endObserver?.cancel()
        endObserver = nil
        loader.stop()
        player.pause()
    }

    func prime() {}
}
