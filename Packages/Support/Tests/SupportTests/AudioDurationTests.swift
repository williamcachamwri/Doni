import AVFoundation
import Foundation
import Testing
@testable import Support

// The fixtures are built rather than kept as sample files: what is under test is the reading of a
// handful of numbers out of a container, and a header three bytes too short has to be expressible.
// Every one of them is the layout the standard describes, at the offsets a real encoder writes.

/// Four ASCII bytes, the way a container spells a type rather than numbers it.
private func four(_ text: String) -> [UInt8] {
    var bytes = [UInt8](text.utf8)
    precondition(bytes.count == 4, "\(text) is not four bytes")
    return bytes
}

private func be32(_ value: Int) -> [UInt8] {
    (0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
}

private func be64(_ value: Int) -> [UInt8] {
    (0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
}

/// RIFF counts are little-endian, whatever the tags beside them are spelled as.
private func le32(_ value: Int) -> [UInt8] {
    (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
}

/// An ISO base media file box: a size that counts itself, a type, and what is inside.
private func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
    be32(payload.count + 8) + four(type) + payload
}

/// The `mvhd` header: two dates, a timescale and a duration, the last two widened to 64 bits in
/// version 1 — which is also what moves them along.
private func mvhd(timescale: Int, duration: Int, version: Int = 0) -> [UInt8] {
    let dates = version == 0 ? be32(0) + be32(0) : be64(0) + be64(0)
    let length = version == 0 ? be32(duration) : be64(duration)
    return box("mvhd", [UInt8(version), 0, 0, 0] + dates + be32(timescale) + length)
}

/// The four bytes of an MPEG layer III frame header: eleven sync bits, the version, the layer, no
/// CRC, stereo, then the two indexes that pick a bitrate and a sample rate out of the same tables
/// the reader uses.
private func frameHeader(version: Int = 3, bitrateIndex: Int = 9, sampleIndex: Int = 0) -> [UInt8] {
    [0xFF, 0xE0 | UInt8(version << 3) | 0x02, UInt8(bitrateIndex << 2) | UInt8(sampleIndex), 0x00]
}

/// A first frame with the encoder's own `Xing` in it, padded so the tag is inside the window the
/// reader looks at and the buffer is long enough for it to be read at all. The tag is its four
/// letters, its flags, and then the fields those flags announce — a frame count is the first.
private func mp3WithXing(frames: Int, tagAt: Int = 36, version: Int = 3, bitrateIndex: Int = 9,
                         sampleIndex: Int = 0) -> [UInt8] {
    var bytes = frameHeader(version: version, bitrateIndex: bitrateIndex, sampleIndex: sampleIndex)
    bytes += [UInt8](repeating: 0, count: tagAt - 4)
    bytes += four("Xing") + be32(0x01) + be32(frames)
    return bytes + [UInt8](repeating: 0, count: 64 - bytes.count % 64)
}

/// An ID3v2 header, whose size is synchsafe: seven bits in each of four bytes.
private func id3(size: Int) -> [UInt8] {
    [0x49, 0x44, 0x33, 0x03, 0x00, 0x00,
     UInt8(truncatingIfNeeded: (size >> 21) & 0x7F), UInt8(truncatingIfNeeded: (size >> 14) & 0x7F),
     UInt8(truncatingIfNeeded: (size >> 7) & 0x7F), UInt8(truncatingIfNeeded: size & 0x7F)]
}

private func data(_ bytes: [UInt8]) -> Data { Data(bytes) }

@Test("an m4a with its moov up front answers from the head alone")
func moovAtTheFront() {
    let head = box("ftyp", four("M4A ") + be32(0) + four("M4A "))
        + box("moov", mvhd(timescale: 44100, duration: 44100 * 212))
    #expect(AudioDuration.read(head: data(head), totalSize: 8_400_000) == .seconds(212))
}

@Test("a 64-bit mvhd is read as well as a 32-bit one")
func mvhdVersionOne() {
    let head = box("ftyp", four("M4A ")) + box("moov", mvhd(timescale: 1000, duration: 5_038_000,
                                                            version: 1))
        + box("free", [UInt8](repeating: 0, count: 64))
    #expect(AudioDuration.read(head: data(head), totalSize: 12_000_000) == .seconds(5038))
}

@Test("an m4a that wrote the audio first is sent to the other end of the file")
func moovAtTheBack() {
    let head = box("ftyp", four("M4A ")) + box("mdat", [UInt8](repeating: 0x55, count: 4096))
    #expect(AudioDuration.read(head: data(head), totalSize: 9_000_000) == .tailNeeded)
    let tail = box("mdat", [UInt8](repeating: 0, count: 16))
        + box("moov", mvhd(timescale: 44100, duration: 44100 * 180))
    #expect(AudioDuration.read(tail: data(tail)) == .seconds(180))
}

@Test("a Xing count is the encoder's own frame count, at either MPEG version")
func xingCountsFrames() {
    // 7656 frames of 1152 samples at 44.1 kHz.
    #expect(AudioDuration.read(head: data(mp3WithXing(frames: 7656)), totalSize: 6_000_000)
            == .seconds(200))
    // 4167 frames of 576 samples at 24 kHz, and its tag sits where a mono frame puts it.
    #expect(AudioDuration.read(head: data(mp3WithXing(frames: 4167, tagAt: 21, version: 2,
                                                                      bitrateIndex: 8,
                                                                      sampleIndex: 1)),
                               totalSize: 2_000_000) == .seconds(100))
}

@Test("no tag means constant bitrate, which the file's own size divides exactly")
func constantBitrateDividesTheSize() {
    let head = frameHeader() + [UInt8](repeating: 0, count: 200)
    // 128 kbps over three million two hundred thousand bytes.
    #expect(AudioDuration.read(head: data(head), totalSize: 3_200_000) == .seconds(200))
}

@Test("a tag bigger than the head is a reason to ask again, not a reason to give up")
func aBigId3TagAsksForMore() {
    let tag = 100_000
    let frame = mp3WithXing(frames: 7656)
    let head = id3(size: 40) + [UInt8](repeating: 0, count: 40) + frame
    #expect(AudioDuration.read(head: data(head), totalSize: 6_000_000) == .seconds(200))
    let shallow = Array((id3(size: tag) + frame + [UInt8](repeating: 0, count: 200_000))
                            .prefix(32 * 1024))
    #expect(AudioDuration.read(head: data(shallow), totalSize: 6_000_000)
            == .headTooSmall(bytes: 104_106))
}

@Test("a VBRI says variable bitrate and keeps its count to itself")
func vbrIsRefusedNotGuessed() {
    var bytes = frameHeader() + [UInt8](repeating: 0, count: 4)
    bytes += four("VBRI") + [UInt8](repeating: 0, count: 60)
    #expect(AudioDuration.read(head: data(bytes), totalSize: 6_000_000) == .nothing)
}

@Test("a number that could not be a song's length is not one")
func implausibleLengthsAreRefused() {
    // One frame is 26 milliseconds; five and a half hours is not a song.
    #expect(AudioDuration.read(head: data(mp3WithXing(frames: 1)), totalSize: 6_000_000) == .nothing)
    #expect(AudioDuration.read(head: data(mp3WithXing(frames: 800_000)), totalSize: 6_000_000)
            == .nothing)
    // A `mvhd` with no timescale, and one with no duration, are both unreadable.
    let noScale = box("ftyp", four("M4A ")) + box("moov", mvhd(timescale: 0, duration: 44100 * 200))
        + box("free", [UInt8](repeating: 0, count: 64))
    #expect(AudioDuration.read(head: data(noScale), totalSize: 8_000_000) == .tailNeeded)
    let noLength = box("ftyp", four("M4A ")) + box("moov", mvhd(timescale: 44100, duration: 0))
        + box("free", [UInt8](repeating: 0, count: 64))
    #expect(AudioDuration.read(head: data(noLength), totalSize: 8_000_000) == .tailNeeded)
}

@Test("bytes that are none of these containers answer nothing")
func anythingElseAnswersNothing() {
    #expect(AudioDuration.read(head: data([0x00, 0x01, 0x02]), totalSize: 3) == .nothing)
    #expect(AudioDuration.read(head: data([UInt8](repeating: 0x11, count: 512)), totalSize: 512)
            == .nothing)
    #expect(AudioDuration.read(tail: data([UInt8](repeating: 0x11, count: 512))) == .nothing)
    // A whole file shorter than a song can be, however it is spelled.
    #expect(AudioDuration.read(head: data(frameHeader() + [UInt8](repeating: 0, count: 40)),
                               totalSize: 45) == .nothing)
}

@Test("a file the phone holds whole is timed by AVFoundation itself")
func readsAFileWhole() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("doni-duration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("two-seconds.wav")
    try wav(seconds: 2, sampleRate: 44100).write(to: url)
    #expect(await AudioDuration.seconds(ofPath: url.path) == 2)
    // Not audio at all, and a file that is not there: nothing to report, rather than a zero a row
    // would draw as `0:00`.
    let junk = directory.appendingPathComponent("nothing.mp3")
    try Data([0x00, 0x01, 0x02]).write(to: junk)
    #expect(await AudioDuration.seconds(ofPath: junk.path) == nil)
    #expect(await AudioDuration.seconds(ofPath: url.path + ".nope") == nil)
}

/// A PCM WAV of `seconds` silence: 16-bit mono at `sampleRate`, so 88 200 bytes to the second.
private func wav(seconds: Int, sampleRate: Int) -> Data {
    let bytes = sampleRate * 2 * seconds
    var out = four("RIFF") + le32(bytes + 36) + four("WAVE")
    out += four("fmt ") + le32(16) + [1, 0] + [1, 0] + le32(sampleRate) + le32(sampleRate * 2)
    out += [2, 0] + [16, 0]
    out += four("data") + le32(bytes) + [UInt8](repeating: 0, count: bytes)
    return Data(out)
}
