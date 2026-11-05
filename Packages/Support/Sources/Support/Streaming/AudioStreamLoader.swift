import AVFoundation
import Foundation

/// Why a range could not be handed to the player.
///
/// These are said out loud rather than answered with silence because a stalled progress bar and a
/// song that has run out of bytes look identical from the screen, and only one of them is the app's
/// fault.
public enum AudioStreamError: Error, Equatable, Sendable {
    /// The file's length is not known, so no byte range can be promised to anything.
    case lengthUnknown
    /// The reader asked for bytes that are not on the phone and nothing arrived for them in time.
    case stalled
}

/// Whoever holds the song's bytes, in ranges.
///
/// The shape is deliberately the smallest one that can still be honest about a partial file: there is
/// no "give me the whole thing" on it, and there is no way to ask for bytes without also saying where
/// the player wants to be, because the only way to get bytes in the middle of a Telegram file is to
/// move the download there.
public protocol AudioByteProviding: Sendable {
    /// The exact size on the server, or `nil` when it is not known — which means nothing can be served.
    func totalBytes() async -> Int64?

    /// The bytes at `offset`, as many as are actually there, `nil` or empty when none are.
    ///
    /// Implementations must not hand back bytes the transport has not declared ready: a Telegram file
    /// on disk is longer than the parts it holds and the gap between them is somebody else's bytes.
    func read(at offset: Int64, count: Int) async -> Data?

    /// Move the fetch to `range`. Called every time `read` came back short, and only then.
    func want(_ range: AudioByteRange) async
}

/// Serves a song to AVFoundation one byte range at a time out of an `AudioByteProviding`.
///
/// This is the piece that decides whether the feature is real. `AVPlayer` will happily read a local
/// file, so a loader that simply read the whole file and handed it over in one `respond(with:)` would
/// play perfectly and still make the user wait for all fifteen megabytes — a download manager with a
/// delegate attached. What makes it streaming is that every answer here is bounded twice over: by
/// what the player asked for, and by what the provider is willing to say is on the device.
///
/// Threading is the other half. AVFoundation calls the delegate on a queue of its own and hands over
/// loading requests it does not describe as `Sendable`, so each request lives in a box with a lock and
/// the answering happens in a task per request, which is also how a cancel from the player is
/// answered — `didCancel` sets the flag the task is about to read.
public final class AudioStreamLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    /// How much of a request is answered in one go. Big enough that the decoder gets a frame
    /// boundary to hold on to, small enough that a truncated answer comes back quickly and the player
    /// asks again rather than waiting for megabytes.
    public static let chunkBytes = 256 * 1024

    /// How often to look again for a range the transport was told about: sixteen times a second,
    /// which is short next to a Telegram part arriving over the network and long next to a disk read.
    static let pollNanoseconds: UInt64 = 60_000_000

    /// How many looks in a row may come back empty before the range is called stalled. Sixteen a
    /// second times twenty-five is the twenty seconds a poor connection takes to move 64 KiB, and it
    /// is a count rather than a clock so a caller can ask for less of it.
    public static let maximumIdlePasses = 25

    /// How many empty passes this loader will wait through for one range.
    private let stallPasses: Int

    /// The uniform type identifier of the container, which the player has to be *told*: a resource
    /// loader is not a URL AVFoundation will probe, and answering the content-information request
    /// without a type is what AVFoundation reports as "the server is not correctly configured"
    /// (-11850) rather than as a missing type.
    private let contentType: String?

    private let source: any AudioByteProviding
    private let queue = DispatchQueue(label: "local.doni.audio.stream-loader", attributes: .concurrent)

    /// One loading request the player is waiting on.
    ///
    /// The cancel flag is behind a lock because the player sets it on its own queue while the serving
    /// task reads it on every pass — a race here is a request answered after the player stopped
    /// listening, which AVFoundation reports as a broken stream rather than as a cancelled one.
    private final class Open: @unchecked Sendable {
        let request: AVAssetResourceLoadingRequest
        private let lock = NSLock()
        private var _cancelled = false

        init(_ request: AVAssetResourceLoadingRequest) { self.request = request }

        var cancelled: Bool { lock.withLock { _cancelled } }
        func cancel() { lock.withLock { _cancelled = true } }
    }

    private var open: [ObjectIdentifier: Open] = [:]

    /// The last reason this loader gave up on a range, which is the only way a caller can tell a
    /// stream that is slow apart from a stream that is dead — and the thing a test asserts on.
    public private(set) var lastError: AudioStreamError?
    private let errorLock = NSLock()

    /// - Parameters:
    ///   - source: whoever holds the bytes.
    ///   - url: the address the asset will be played from, made by `url(for:fileType:)`. The type is
    ///     taken from its extension because a URL and a container that disagree about what they are
    ///     is a bug no player can recover from.
    public init(source: any AudioByteProviding, url: URL,
                stallPasses: Int = AudioStreamLoader.maximumIdlePasses) {
        self.source = source
        self.contentType = AudioContentType.uti(forExtension: url.pathExtension)
        self.stallPasses = max(1, stallPasses)
        super.init()
    }

    /// The address a song is played from: a scheme of this app's own, with the file's durable
    /// identity in the query so a byte provider can be asked about it and nothing else.
    ///
    /// The extension is carried in the path because AVFoundation reads the URL's name when it has to
    /// guess a container, and a song named only by a hash costs it a probe of the head instead.
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
            // The two things the player needs before it will treat a stream as seekable: the exact
            // size of the thing, and permission to come back for any range of it. Without byte-range
            // access AVFoundation asks for the file to the end and the loader is a downloader again.
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
        // Idleness is counted in passes rather than in seconds: a stream that is going to arrive may
        // take a minute to do it on a bad connection and must not be called broken because of it,
        // while a stream that has stopped answers with nothing on every single pass. A caller that
        // wants the give-up sooner — a test, or a phone on a network it knows is down — passes a
        // smaller number in.
        var idle = 0
        while !held.cancelled {
            let offset = data.currentOffset
            // Exactly as much as this request still wants, never more. AVFoundation opens a stream
            // with a two-byte probe (`requestedLength: 2`) and a delegate that answers it with a
            // megabyte is answered back with -11850 "the server is not correctly configured": the
            // parser asked for a nibble, got a mouthful it had no offsets for, and gave up.
            let asked = Int64(data.requestedLength)
            let remaining = asked > 0 ? asked - (offset - Int64(data.requestedOffset)) : Int64(Self.chunkBytes)
            let count = max(1, min(Self.chunkBytes, Int(min(remaining, Int64(Self.chunkBytes)))))
            if let bytes = await source.read(at: offset, count: count), !bytes.isEmpty {
                idle = 0
                data.respond(with: bytes)
                if isSatisfied(data, by: offset + Int64(bytes.count)) {
                    if !held.cancelled { held.request.finishLoading() }
                    drop(held)
                    return
                }
                continue
            }
            // Nothing there yet: say where the player is, and go round again. This is the seek — the
            // transport is told to fetch from this offset, not from the beginning of the song.
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
    /// A request with no length is "give me everything to the end of the file", which is true of the
    /// first probe AVFoundation makes when it does not yet know the format. Answering it in full is
    /// the download-manager mistake; here it is answered as far as the bytes happen to reach, and the
    /// player comes back for a range when it needs more — which is exactly the conversation a server
    /// that supports byte ranges has with a client.
    private func isSatisfied(_ data: AVAssetResourceLoadingDataRequest, by end: Int64) -> Bool {
        let asked = Int64(data.requestedLength)
        if asked > 0 { return end >= Int64(data.requestedOffset) + asked }
        return false
    }

    private func finish(_ held: Open, with error: AudioStreamError) {
        errorLock.withLock { lastError = error }
        if !held.cancelled { held.request.finishLoading(with: error) }
        drop(held)
    }

    private func drop(_ held: Open) {
        queue.sync(flags: .barrier) {
            open[ObjectIdentifier(held.request)] = nil
        }
    }
}
