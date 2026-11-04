import AVFoundation
import CoreMedia
import Foundation

/// How long a song is, in whole seconds.
///
/// Telegram only says it when the post is a `messageAudio` (`td_api.tl:583` has `duration`). The
/// same song posted as a `messageDocument` (`:594`) arrives with a name, a mime type and a size and
/// nothing else — the schema has no duration there, and TDLib does not open the container to fill
/// one in. So the app measures, in one of two ways:
///
/// * `seconds(ofPath:)` reads a file the phone already holds whole;
/// * `read(head:totalSize:)` reads a few hundred bytes of a file it does not, which is the only way
///   a list of songs nobody has ever played can show a timestamp at all.
///
/// A measurement is written into the store and kept: the walk that re-reads the channel sends a
/// `NULL` duration for a document row, and the upsert's `COALESCE` leaves the number the app
/// measured alone.
public enum AudioDuration {
    /// The length of a file that is on the device.
    ///
    /// `AVURLAsset` rather than a hand-rolled parse: the file is whole here, so the answer is the
    /// container's own, and Apple's readers already know a 32-bit `mvhd` from a 64-bit one. The
    /// metadata is resolved without loading the audio, so this is a header read and not a decode.
    public static func seconds(ofPath path: String) async -> Int? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return checked(seconds)
    }

    /// A song is between these. Outside them the bytes that made the number were not a duration,
    /// which is the whole defence against reading a length out of an audio sample that happens to
    /// spell the right pattern.
    private static func checked(_ seconds: Double) -> Int? {
        guard seconds.isFinite, seconds >= 1, seconds <= 3 * 3600 else { return nil }
        return Int(seconds.rounded())
    }

    // MARK: From a few bytes

    /// What a handful of bytes at one end of a file say about its length.
    public enum Reading: Equatable {
        /// The container said it.
        case seconds(Int)
        /// An MP3 whose ID3v2 tag is bigger than the bytes handed over. The cover art lives inside
        /// that tag, and the first audio frame — where the length is written — starts after it, so
        /// the ask has to be made again for `bytes`.
        case headTooSmall(bytes: Int)
        /// An MP4 written with the audio first: its `moov`, and the `mvhd` inside it, are at the
        /// other end of the file, where the head cannot reach.
        case tailNeeded
        /// Not one of the containers this reads, or nothing in it that could pass for a length.
        case nothing
    }

    /// `head` is the first bytes of the file and `totalSize` its size on the server — TDLib knows
    /// both without the file (`td_api.tl:326`), and a constant-bitrate MP3 has to divide the second.
    public static func read(head: Data, totalSize: Int64) -> Reading {
        let bytes = [UInt8](head)
        guard bytes.count >= 10 else { return .nothing }
        if isMp4(bytes) {
            return mvhdSeconds(in: bytes).map(Reading.seconds) ?? .tailNeeded
        }
        var start = 0
        if bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {  // "ID3", three letters not four
            // Bytes 6 through 9 are the tag's size, and synchsafe: seven bits per byte, so the
            // ordinary read of the same four is 128× too big. Everything after the ten-byte header,
            // extended header included, is inside that size.
            let size = (Int(bytes[6]) << 21) | (Int(bytes[7]) << 14) | (Int(bytes[8]) << 7) | Int(bytes[9])
            start = 10 + size
            guard start < bytes.count else { return .headTooSmall(bytes: start + 4096) }
        }
        return mp3Seconds(in: bytes, from: start, totalSize: totalSize)
    }

    /// The last bytes of a file, for the MP4s that keep their `moov` after the audio.
    public static func read(tail: Data) -> Reading {
        mvhdSeconds(in: [UInt8](tail)).map(Reading.seconds) ?? .nothing
    }

    /// ISO base media files — m4a among them — open with a box, and the type spelled at byte four
    /// says which family this is. Anything else does not start with a box.
    private static func isMp4(_ bytes: [UInt8]) -> Bool {
        ["ftyp", "styp", "moov", "mdat", "free", "skip", "uuid", "pnot"].contains(ascii(bytes, 4))
    }

    /// The `mvhd` header: a timescale and a duration, whose quotient is the length.
    ///
    /// Scanned for rather than walked to, because a tail slice holds no box tree — the atom is
    /// somewhere in the middle of what was read and only its own four letters say so. Both the 32-bit
    /// and the 64-bit forms are read, and every candidate has to come out as a length a song could
    /// actually be before it is believed.
    private static func mvhdSeconds(in bytes: [UInt8]) -> Int? {
        let tag: [UInt8] = [0x6D, 0x76, 0x68, 0x64]  // "mvhd"
        var at = 0
        while at + 40 <= bytes.count {
            guard let found = index(of: tag, in: bytes, from: at) else { return nil }
            at = found
            defer { at += 4 }
            let version = bytes[found + 4]
            guard version < 2 else { continue }
            // After the tag: version and flags (4), then two dates, then the timescale and the
            // duration. Version 1 makes the dates 64-bit, which shifts both fields along — and makes
            // the duration 64-bit too.
            let timescale = version == 0 ? be32(bytes, found + 16) : be32(bytes, found + 24)
            let duration = version == 0 ? be32(bytes, found + 20) : be64(bytes, found + 28)
            guard timescale > 0, timescale < 10_000_000, duration > 0 else { continue }
            if let seconds = checked(Double(duration) / Double(timescale)) { return seconds }
        }
        return nil
    }

    // MARK: MP3

    /// The length from the first MPEG layer III frame: the encoder's own frame count when it wrote
    /// one, and the bitrate divided into the file's size when it did not.
    ///
    /// LAME — what every bot here encodes with — writes a `Xing` tag into the first frame for
    /// variable-bitrate files, and that count is exact. Without any tag the file is constant bitrate
    /// and the division is exact too. `VBRI` is the one case where neither holds: it also means
    /// variable bitrate but keeps its count in a layout of its own, so it is refused rather than
    /// guessed at.
    private static func mp3Seconds(in bytes: [UInt8], from start: Int,
                                   totalSize: Int64) -> Reading {
        guard let frame = firstMp3Frame(in: bytes, from: start) else { return .nothing }
        switch vbrTag(in: bytes, at: frame.at) {
        case let .frames(count):
            let seconds = Double(count) * Double(frame.samplesPerFrame) / Double(frame.sampleRate)
            return checked(seconds).map(Reading.seconds) ?? .nothing
        case .unreadable:
            return .nothing
        case nil:
            // Constant bitrate: every frame is the same size, so the whole file is one long frame.
            // A trailing ID3v1 tag of 128 bytes is counted as audio, which is a fifth of a second at
            // 128 kbps and rounds away.
            let audio = totalSize - Int64(frame.at)
            guard audio > 0 else { return .nothing }
            return checked(Double(audio) * 8 / Double(frame.bitrate * 1000))
                .map(Reading.seconds) ?? .nothing
        }
    }

    /// An MP3 frame header, and the three numbers that follow from it.
    private struct Mp3Frame {
        let at: Int
        let bitrate: Int
        let sampleRate: Int
        let samplesPerFrame: Int
    }

    private static func firstMp3Frame(in bytes: [UInt8], from start: Int) -> Mp3Frame? {
        var at = start
        // A tag can be padded, but 64 KB without a sync word is not a file this should keep
        // scanning — by then the buffer was the wrong answer anyway.
        while at + 4 <= bytes.count, at - start < 64 * 1024 {
            if let frame = mp3Frame(in: bytes, at: at) { return frame }
            at += 1
        }
        return nil
    }

    /// The 32 bits of a frame header, or nil for four bytes that are not one. `0xFF`, eleven sync
    /// bits, then the version, the layer, and the two indexes that pick a bitrate and a sample rate
    /// out of the tables below (`ISO/IEC 11172-3` and `13818-3`, table III.23).
    private static func mp3Frame(in bytes: [UInt8], at: Int) -> Mp3Frame? {
        guard bytes[at] == 0xFF, bytes[at + 1] & 0xE6 == 0xE2 else { return nil }
        // Byte 1: bits 4-3 version (3 MPEG-1, 2 MPEG-2, 0 MPEG-2.5, 1 reserved),
        //         bits 2-1 layer (1 layer III, 0 reserved), bit 0 protection (1 means no CRC).
        let versionBits = Int((bytes[at + 1] >> 3) & 0x03)
        let layerBits = Int((bytes[at + 1] >> 1) & 0x03)
        // Byte 2: bits 7-6 channel mode, bits 5-2 the bitrate index, bits 1-0 the sample rate.
        let bitrateIndex = Int((bytes[at + 2] >> 2) & 0x0F)
        let sampleIndex = Int(bytes[at + 2] & 0x03)
        guard versionBits != 1, layerBits == 1, bitrateIndex > 0, bitrateIndex < 15,
              sampleIndex < 3 else { return nil }
        let isMpeg1 = versionBits == 3
        let bitrates = isMpeg1 ? mp3BitratesMpeg1 : mp3BitratesMpeg2
        let sampleRates = mp3SampleRates[isMpeg1 ? 0 : versionBits == 2 ? 1 : 2]
        return Mp3Frame(at: at, bitrate: bitrates[bitrateIndex - 1], sampleRate: sampleRates[sampleIndex],
                        samplesPerFrame: isMpeg1 ? 1152 : 576)
    }

    /// MPEG-1 layer III: 32 kbps at index 1 up to 320 at index 14.
    private static let mp3BitratesMpeg1 = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
    /// MPEG-2 and MPEG-2.5 layer III: 8 kbps at index 1 up to 160 at index 14.
    private static let mp3BitratesMpeg2 = [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
    private static let mp3SampleRates = [[44100, 48000, 32000], [22050, 24000, 16000],
                                         [11025, 12000, 8000]]

    /// The encoder's tag inside the first frame, if there is one.
    ///
    /// `Xing` and `Info` sit 36 bytes into a stereo MPEG-1 frame and 21 into a mono one, two later
    /// still when a CRC follows the header, and the `VBRI` that some encoders write instead of them
    /// sits nearer the start again — so it is a run of a few dozen bytes rather than a position that
    /// can be re-derived from the header. Anything in that run that spells a tag is read, and a
    /// number that turns out not to be a song length is rejected by the same gate as everything else.
    private enum VbrTag {
        case frames(Int)
        /// A tag that means variable bitrate and does not say how many frames.
        case unreadable
    }

    private static func vbrTag(in bytes: [UInt8], at frame: Int) -> VbrTag? {
        guard frame + 64 <= bytes.count else { return nil }
        for offset in 8..<48 {
            switch ascii(bytes, frame + offset) {
            case "VBRI": return .unreadable
            case "Xing", "Info":
                // The four bytes after the tag are its flags, and bit 0 of them says a frame count
                // follows at +8. The field is big-endian, so that bit is in its last byte.
                guard be32(bytes, frame + offset + 4) & 0x01 != 0 else { return .unreadable }
                return .frames(Int(be32(bytes, frame + offset + 8)))
            default: continue
            }
        }
        return nil
    }

    // MARK: Bytes

    /// A pattern in a buffer, from `from` on.
    private static func index(of pattern: [UInt8], in bytes: [UInt8], from: Int) -> Int? {
        guard from >= 0, bytes.count >= from + pattern.count else { return nil }
        var at = from
        while at + pattern.count <= bytes.count {
            var matched = 0
            while matched < pattern.count, bytes[at + matched] == pattern[matched] {
                matched += 1
            }
            if matched == pattern.count { return at }
            at += 1
        }
        return nil
    }

    /// Four bytes as big-endian. `-1` for a run that is not all there, which every caller rejects
    /// because no field of a container is ever negative.
    private static func be32(_ bytes: [UInt8], _ at: Int) -> Int64 {
        guard at >= 0, bytes.count >= at + 4 else { return -1 }
        return (Int64(bytes[at]) << 24) | (Int64(bytes[at + 1]) << 16)
            | (Int64(bytes[at + 2]) << 8) | Int64(bytes[at + 3])
    }

    private static func be64(_ bytes: [UInt8], _ at: Int) -> Int64 {
        guard at >= 0, bytes.count >= at + 8 else { return -1 }
        var value: Int64 = 0
        for step in 0..<8 { value = (value << 8) | Int64(bytes[at + step]) }
        return value
    }

    /// Four bytes read as ASCII, for the tags a container spells rather than numbers.
    private static func ascii(_ bytes: [UInt8], _ at: Int) -> String {
        guard at >= 0, bytes.count >= at + 4 else { return "" }
        return String(decoding: bytes[at..<at + 4], as: UTF8.self)
    }
}
