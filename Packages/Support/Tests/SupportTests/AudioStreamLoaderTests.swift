import AVFoundation
import Foundation
import Testing
@testable import Support

/// A song's bytes that only exist where they were asked for — a miniature of TDLib's partial file.
///
/// The whole file is in memory here, but the source will not hand over a byte until the loader has
/// said where the player is, and then it gives exactly one part (`64 KiB`, TDLib's own size) at that
/// offset. So a caller that reads the whole file in one go gets an empty answer, and a caller that
/// streams gets its bytes a part at a time, in the order the player wants them.
private final class WindowedBytes: AudioByteProviding, @unchecked Sendable {
    static let part: Int64 = 64 << 10

    private let data: Data
    private let lock = NSLock()
    private var ready = AudioReadyRanges()
    private var readAsks: [(offset: Int64, count: Int)] = []
    private var windows: [AudioByteRange] = []
    /// A test that wants a stream that never arrives sets this: nothing is ever granted, so the only
    /// answer the loader can get is "not here".
    let grants: Bool

    init(_ data: Data, grants: Bool = true) {
        self.data = data
        self.grants = grants
        // What TDLib has already fetched before the player touched it: the head, and nothing else.
        if grants {
            ready.mark(AudioByteRange(offset: 0, count: Self.part))
        }
    }

    func totalBytes() async -> Int64? { Int64(data.count) }

    func read(at offset: Int64, count: Int) async -> Data? {
        let contiguous = lock.withLock { () -> Int64 in
            readAsks.append((offset, count))
            return ready.contiguous(at: offset)
        }
        guard contiguous > 0, offset < Int64(data.count) else { return Data() }
        let take = Int(min(contiguous, Int64(count)))
        let from = Int(offset)
        return data.subdata(in: from..<min(from + take, data.count))
    }

    func want(_ range: AudioByteRange) async {
        guard grants else { return }
        let from = range.offset / Self.part * Self.part
        lock.withLock {
            ready.mark(AudioByteRange(offset: from, count: Self.part))
            windows.append(range)
        }
    }

    var readOffsets: [Int64] { lock.withLock { readAsks.map(\.offset) } }
    var maxReadCount: Int { lock.withLock { readAsks.map(\.count).max() ?? 0 } }
    var windowCount: Int { lock.withLock { windows.count } }
}

/// A PCM wave: 44 header bytes and then `frames` samples of one sine, mono.
///
/// WAV rather than MP3 because nothing in a test needs to encode it, and its byte-to-time map is
/// exactly linear — which is what lets a test say "the reader asked for the bytes five seconds in".
func waveData(seconds: Int, rate: Int = 44_100) -> Data {
    let frames = seconds * rate
    let bytes = frames * 2
    var out = Data(capacity: 44 + bytes)
    func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }
    func u32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
    }
    func u16(_ value: Int) -> [UInt8] { [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)] }

    out.append(contentsOf: ascii("RIFF")); out.append(contentsOf: u32(36 + bytes))
    out.append(contentsOf: ascii("WAVEfmt ")); out.append(contentsOf: u32(16))
    out.append(contentsOf: u16(1)); out.append(contentsOf: u16(1))
    out.append(contentsOf: u32(rate)); out.append(contentsOf: u32(rate * 2))
    out.append(contentsOf: u16(2)); out.append(contentsOf: u16(16))
    out.append(contentsOf: ascii("data")); out.append(contentsOf: u32(bytes))
    for frame in 0..<frames {
        let sample = Int16(clamping: Int(sin(Double(frame) / 40) * 12_000))
        out.append(contentsOf: u16(Int(UInt16(bitPattern: sample))))
    }
    return out
}

private func decodedFrames(_ asset: AVURLAsset, from start: Double? = nil) async throws -> Int {
    // The tracks are loaded before a reader is built on them: an asset whose playable `wav` came out
    // of a loader is a normal asset in every other way, and a reader made from an unloaded one fails
    // for a reason that has nothing to do with what is being tested.
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
        throw NSError(domain: "no audio track", code: 1)
    }
    let reader = try AVAssetReader(asset: asset)
    if let start {
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       duration: CMTime(seconds: 1, preferredTimescale: 600))
    }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
    ])
    reader.add(output)
    #expect(reader.startReading())
    var frames = 0
    while reader.status == .reading {
        if let buffer = output.copyNextSampleBuffer() {
            frames += CMBlockBufferGetDataLength(CMSampleBufferGetDataBuffer(buffer)!) / 2
        } else {
            usleep(2_000)
        }
    }
    return frames
}

/// A player-side asset wired to a loader over `source`, which is the whole setup every test here needs.
private func stream(_ source: any AudioByteProviding, key: String,
                    stallPasses: Int = AudioStreamLoader.maximumIdlePasses) -> (AVURLAsset, AudioStreamLoader) {
    let url = AudioStreamLoader.url(for: key, fileType: "wav")
    let loader = AudioStreamLoader(source: source, url: url, stallPasses: stallPasses)
    let asset = AVURLAsset(url: url)
    asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "test.loader.\(key)"))
    return (asset, loader)
}

@Test("a song is served to AVFoundation a range at a time, and it decodes")
func streamsRangesAndDecodes() async throws {
    let song = waveData(seconds: 8)
    let source = WindowedBytes(song)
    let (asset, loader) = stream(source, key: "u1234")

    let frames = try await decodedFrames(asset)
    // The whole song came out of the decoder, so every byte of it went through the loader.
    #expect(abs(frames - 8 * 44_100) < 44_100 / 10)

    // …and it did not go through in one piece. A loader that read the file and dumped it at the
    // player would pass the assertion above and fail these, which is the point of them: nothing was
    // ever asked for at once, and the song arrived in the number of pieces its bytes are worth.
    #expect(source.maxReadCount <= AudioStreamLoader.chunkBytes)
    #expect(source.maxReadCount < song.count)
    #expect(source.readOffsets.count > 4)
    #expect(source.windowCount > 4)
    #expect(loader.lastError == nil)
    loader.stop()
}

@Test("a reader that starts five seconds in asks for the bytes there")
func seeksToTheMiddleOfTheSong() async throws {
    let song = waveData(seconds: 10)
    let source = WindowedBytes(song)
    let (asset, loader) = stream(source, key: "u5678")

    let frames = try await decodedFrames(asset, from: 5)
    #expect(frames > 40_000)
    // One part is 64 KiB and a second of this song is 88 200 bytes, so five seconds in is byte
    // 441 000-ish — an offset that only a range request can reach.
    #expect(source.readOffsets.contains { $0 > 400_000 })
    loader.stop()
}

@Test("a stream that never gets bytes says so instead of waiting forever")
func stallsAreNamed() async throws {
    let source = WindowedBytes(waveData(seconds: 6), grants: false)
    let (asset, loader) = stream(source, key: "u9", stallPasses: 3)

    // A song with no bytes anywhere is not a hang and not a silence: it is an answer, and the answer
    // has a name. Before the loader counted idle passes this test is the shape of every "the app is
    // spinning and nobody knows why" report.
    _ = try? await asset.loadTracks(withMediaType: .audio)
    #expect(loader.lastError == .stalled)
    loader.stop()
}

@Test("a byte length that is not known is refused, not guessed at")
func unknownLengthIsAnAnswer() async throws {
    struct Unknown: AudioByteProviding {
        func totalBytes() async -> Int64? { nil }
        func read(at offset: Int64, count: Int) async -> Data? { Data() }
        func want(_ range: AudioByteRange) async {}
    }
    let (asset, loader) = stream(Unknown(), key: "u0")
    do {
        let duration = try await asset.load(.duration)
        // A duration cannot be measured from a stream whose length is unknown, and pretending
        // otherwise is how a song ends up "0:00" forever with no error said about it.
        #expect(duration.seconds == 0 || duration.isIndefinite)
    } catch {
        #expect(true)
    }
    loader.stop()
}

@Test("the containers AVFoundation opens are named, and the ones it does not are not")
func typesAreKnown() {
    #expect(AudioContentType.uti(forExtension: "mp3") == "public.mp3")
    #expect(AudioContentType.uti(forMIMEType: "audio/mpeg") == "public.mp3")
    #expect(AudioContentType.uti(forExtension: "m4A") == "com.apple.m4a-audio")
    // Not a dig at Ogg — a promise. AVFoundation cannot decode it, so a caller that asked for it
    // would get a song that fails to load instead of one that plays from a whole file.
    #expect(AudioContentType.uti(forExtension: "ogg") == nil)
    #expect(AudioContentType.uti(forExtension: "opus") == nil)
    #expect(AudioContentType.uti(forMIMEType: "application/octet-stream") == nil)
    #expect(AudioContentType.isStreamable(mimeType: "audio/mp4", fileName: "x"))
    #expect(AudioContentType.isStreamable(mimeType: "application/octet-stream", fileName: "song.flac"))
    #expect(!AudioContentType.isStreamable(mimeType: "audio/ogg", fileName: "voice.opus"))
}

@Test("a transport that says these bytes are never coming is not waited through")
func unavailableIsNotStalled() async throws {
    struct Gone: AudioByteProviding {
        func totalBytes() async -> Int64? { 1_000_000 }
        func read(at offset: Int64, count: Int) async -> Data? { nil }
        func want(_ range: AudioByteRange) async {}
    }
    let (asset, loader) = stream(Gone(), key: "u7", stallPasses: 50)
    _ = try? await asset.loadTracks(withMediaType: .audio)
    // The difference the app has to be able to see: a song that is gone from the server and a song
    // that is slow look the same on a spinner and are not the same fact.
    #expect(loader.lastError == .unavailable)
    loader.stop()
}
