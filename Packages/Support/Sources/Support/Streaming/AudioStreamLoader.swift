import AVFoundation
import Foundation

/// Why a range could not be handed to the player, said out loud rather than answered with silence:
/// a stalled progress bar and a song out of bytes look identical on screen.
public enum AudioStreamError: Error, Equatable, Sendable {
    /// The file's length is not known, so no byte range can be promised to anything.
    case lengthUnknown
    /// The reader asked for bytes that are not on the phone and nothing arrived for them in time.
    case stalled
    /// The transport says these bytes are never coming — gone from the server, or the row number asked
    /// with belongs to another song. Waiting on this is pointless where `stalled` is only slow.
    case unavailable
}

/// Whoever holds the song's bytes, in ranges.
///
/// The smallest shape still honest about a partial file: no "give me the whole thing", and no asking
/// for bytes without saying where the player wants to be — moving the download is the only way.
public protocol AudioByteProviding: Sendable {
    /// The exact size on the server, or `nil` when it is not known — which means nothing can be served.
    func totalBytes() async -> Int64?

    /// The bytes at `offset`, as many as are actually there.
    ///
    /// Implementations must not hand back bytes the transport has not declared ready: a Telegram file
    /// on disk is longer than its parts and the gap between them is somebody else's bytes. An empty
    /// answer means "not yet" and is waited through; `nil` means "not ever" and ends the request.
    func read(at offset: Int64, count: Int) async -> Data?

    /// Move the fetch to `range`. Called every time `read` came back short, and only then.
    func want(_ range: AudioByteRange) async
}

/// Serves a song to AVFoundation one byte range at a time out of an `AudioByteProviding`.
///
/// What makes it streaming rather than a download manager with a delegate attached is that every
/// answer here is bounded twice: by what the player asked for, and by what the provider says is on
/// the device.
///
/// AVFoundation calls the delegate on a queue of its own with requests it does not describe as
/// `Sendable`, so each one lives in a box with a lock and is answered in a task per request — which
/// is also how `didCancel` is answered: it sets the flag that task is about to read.
public final class AudioStreamLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    /// How much of a request is answered in one go: big enough for the decoder to get a frame
    /// boundary, small enough that a truncated answer comes back quickly.
    public static let chunkBytes = 256 * 1024

    /// How often to look again for a range the transport was told about: short next to a Telegram
    /// part arriving over the network, long next to a disk read.
    static let pollNanoseconds: UInt64 = 60_000_000

    /// How many "not yet" looks before the range is called stalled: at sixty milliseconds a look, five
    /// hundred is half a minute — measured, not guessed. On a phone's connection a 64 KiB Telegram
    /// part lands one to eight seconds after being asked, so giving up early breaks on every seek.
    public static let maximumIdlePasses = 500

    /// How many empty passes this loader will wait through for one range.
    private let stallPasses: Int

    /// The uniform type identifier of the container, which the player has to be *told*: a resource
    /// loader is not a URL AVFoundation probes, and answering content-information without a type is
    /// reported as "the server is not correctly configured" (-11850), not as a missing type.
    private let contentType: String?

    private let source: any AudioByteProviding
    private let queue = DispatchQueue(label: "local.doni.audio.stream-loader", attributes: .concurrent)

    /// One loading request the player is waiting on.
    ///
    /// The cancel flag is behind a lock: the player sets it on its own queue while the serving task
    /// reads it every pass, and answering after the player stopped listening is a broken stream.
    private final class Open: @unchecked Sendable {
        let request: AVAssetResourceLoadingRequest
        private let lock = NSLock()
        private var _cancelled = false

        init(_ request: AVAssetResourceLoadingRequest) { self.request = request }

        var cancelled: Bool { lock.withLock { _cancelled } }
        func cancel() { lock.withLock { _cancelled = true } }
    }

    private var open: [ObjectIdentifier: Open] = [:]

    /// The last reason this loader gave up on a range — the only way to tell a slow stream from a dead
    /// one, and what a test asserts on.
    public private(set) var lastError: AudioStreamError?
    private let errorLock = NSLock()

    /// Said as soon as a range is given up on, not left for a caller to notice by polling: a player
    /// still drawing a progress bar across a stopped song needs it the moment the bytes are not coming.
    public var onFailure: (@Sendable (AudioStreamError) -> Void)?

    /// - Parameters:
    ///   - source: whoever holds the bytes.
    ///   - url: the address the asset plays from, made by `url(for:fileType:)`; its extension is the
    ///     container, since a URL and a container that disagree is a bug no player can recover from.
    public init(source: any AudioByteProviding, url: URL,
                stallPasses: Int = AudioStreamLoader.maximumIdlePasses) {
        self.source = source
        self.contentType = AudioContentType.uti(forExtension: url.pathExtension)
        self.stallPasses = max(1, stallPasses)
        super.init()
    }

    /// The address a song is played from: a scheme of this app's own, with the file's durable identity
    /// in the query so a byte provider is asked about it and nothing else. The extension rides in the
    /// path because AVFoundation reads the URL's name to guess a container.
    public static func url(for key: String, fileType: String) -> URL {
        let name = fileType.isEmpty ? "audio" : "audio.\(fileType)"
        var components = URLComponents()
        components.scheme = "doni-audio"
        components.host = "song"
        components.path = "/\(name)"
        components.queryItems = [.init(name: "key", value: key)]
        return components.url!
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                               shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest)
    -> Bool {
        let held = Open(loadingRequest)
        queue.sync(flags: .barrier) { open[ObjectIdentifier(loadingRequest)] = held }
        Task { await serve(held) }
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                               didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        queue.sync(flags: .barrier) {
            guard let held = open.removeValue(forKey: ObjectIdentifier(loadingRequest)) else { return }
            held.cancel()
        }
    }

    public func stop() {
        queue.sync(flags: .barrier) {
            for held in open.values { held.cancel() }
            open.removeAll()
        }
    }

    // MARK: Serving

    private func serve(_ held: Open) async {
        let request = held.request
        if let info = request.contentInformationRequest {
            // What makes a stream seekable to the player: the exact size, and permission to come back
            // for any range. Without byte-range access the loader is a downloader again.
            info.isByteRangeAccessSupported = true
            info.contentType = contentType
            if let total = await source.totalBytes() {
                info.contentLength = total
            } else {
                finish(held, with: .lengthUnknown)
                return
            }
        }
        guard let data = request.dataRequest else {
            request.finishLoading()
            drop(held)
            return
        }
        await serve(data, for: held)
    }

    private func serve(_ data: AVAssetResourceLoadingDataRequest, for held: Open) async {
        // Idleness is counted in passes rather than seconds: a stream that is going to arrive may take
        // a minute on a bad connection and must not be called broken for it, while one that stopped
        // answers with nothing on every pass. A caller wanting the give-up sooner passes a smaller number.
        var idle = 0
        while !held.cancelled {
            let offset = data.currentOffset
            // Exactly as much as this request still wants, never more. AVFoundation opens a stream with
            // a two-byte probe (`requestedLength: 2`), and a delegate answering it with a megabyte is
            // answered back with -11850: the parser asked for a nibble and gave up.
            let asked = Int64(data.requestedLength)
            let remaining = asked > 0 ? asked - (offset - Int64(data.requestedOffset)) : Int64(Self.chunkBytes)
            let count = max(1, min(Self.chunkBytes, Int(min(remaining, Int64(Self.chunkBytes)))))
            guard let got = await source.read(at: offset, count: count) else {
                finish(held, with: .unavailable)
                return
            }
            if !got.isEmpty {
                idle = 0
                data.respond(with: got)
                if isSatisfied(data, by: offset + Int64(got.count)) {
                    if !held.cancelled { held.request.finishLoading() }
                    drop(held)
                    return
                }
                continue
            }
            // Nothing there yet: say where the player is and go round again — the seek tells the
            // transport to fetch from this offset, not from the beginning of the song.
            await source.want(AudioByteRange(offset: offset, count: Int64(Self.chunkBytes * 4)))
            idle += 1
            if idle >= stallPasses {
                finish(held, with: .stalled)
                return
            }
            try? await Task.sleep(nanoseconds: Self.pollNanoseconds)
        }
        drop(held)
    }

    /// Whether the player has now been given everything it asked for in this request.
    ///
    /// A request with no length is "everything to the end of the file", the first probe AVFoundation
    /// makes before it knows the format; answering it in full is the download-manager mistake, so it
    /// is answered as far as the bytes reach and the player comes back for a range.
    private func isSatisfied(_ data: AVAssetResourceLoadingDataRequest, by end: Int64) -> Bool {
        let asked = Int64(data.requestedLength)
        if asked > 0 { return end >= Int64(data.requestedOffset) + asked }
        return false
    }

    private func finish(_ held: Open, with error: AudioStreamError) {
        let first = errorLock.withLock { () -> Bool in
            let wasEmpty = lastError == nil
            lastError = error
            return wasEmpty
        }
        if first { onFailure?(error) }
        if !held.cancelled { held.request.finishLoading(with: error) }
        drop(held)
    }

    private func drop(_ held: Open) {
        queue.sync(flags: .barrier) {
            open[ObjectIdentifier(held.request)] = nil
        }
    }
}
