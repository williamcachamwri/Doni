import Foundation

/// Where TDLib's one download window has to sit for the sound to stay ahead of the playhead.
///
/// Seconds map to bytes as `size / duration`: exact for the constant-bitrate MP3s these channels post,
/// a few percent off for a variable-bitrate one. That is allowed here and nowhere else — this number
/// only decides *which bytes to fetch next*, while the position the user sees and a seek lands at come
/// from the player's own clock.
///
/// TDLib holds exactly one offset and one limit per file (`FileManager.cpp:3103-3107`) and moves the
/// window of a download already in place rather than adding a second one, so the job is saying when it
/// has to move and when it must not: a window re-asked every quarter-second cancels and restarts its
/// own parts.
public struct AudioWindowPolicy: Sendable {
    /// TDLib's part size under 250 MB (`PartsManager.cpp:132`, `MAX_PART_SIZE` at `:56`). Windows start
    /// on this grid: a part is readable only from its start, so an odd offset buys unusable bytes.
    public static let partBytes: Int64 = 64 << 10

    /// A quarter of a minute at 320 kbps. Under this the sound runs out on a hiccup.
    public static let minimumLeadBytes: Int64 = 1 << 20
    /// Twenty seconds of a lossless file. Over this the app is downloading a song's tail before it
    /// has listened to its middle, which is the behaviour this whole feature is meant to end.
    public static let maximumLeadBytes: Int64 = 12 << 20
    /// What a start needs: enough for the decoder to find a frame boundary and report a duration.
    public static let headBytes: Int64 = 768 << 10
    /// An m4a's `moov` atom is at the end of the file, so a player that has only the head cannot find
    /// the track lengths at all. One megabyte covers the metadata of any file these channels post.
    public static let tailBytes: Int64 = 1 << 20

    /// The lead the next window is planned with: grows on a rebuffer, shrinks when the buffer held.
    public private(set) var leadBytes: Int64

    /// The window last asked for, so a plan that has not moved is detected rather than re-sent.
    public private(set) var asked: AudioByteRange?

    public init(leadBytes: Int64 = AudioWindowPolicy.minimumLeadBytes) {
        self.leadBytes = min(Self.maximumLeadBytes, max(Self.minimumLeadBytes, leadBytes))
    }

    /// The playhead's byte, snapped down onto TDLib's part grid.
    public static func aligned(_ bytes: Int64) -> Int64 {
        max(0, bytes / partBytes * partBytes)
    }

    /// The playhead's byte in a file of `fileBytes` at `seconds`, clamped so a seek to the very end
    /// plans the last part rather than a window past the file.
    public static func byteOffset(seconds: Double, bytesPerSecond: Double, fileBytes: Int64) -> Int64 {
        guard fileBytes > 0, seconds > 0, bytesPerSecond > 0 else { return 0 }
        let wanted = Int64(seconds * bytesPerSecond)
        return min(aligned(max(0, wanted - partBytes)), max(0, fileBytes - 1))
    }

    /// The window to ask for at the playhead, or `nil` when the one asked for is still worth keeping.
    ///
    /// Kept until half of it has been listened to: a window covers `leadBytes` of song, and re-asking
    /// when the playhead leaves it would re-ask every quarter second, cancelling the parts outside it
    /// that were already arriving (`FileDownloader.cpp:469-474`). Half is one request per half-window —
    /// about one every twelve seconds at 320 kbps. The playhead sits inside the window, one part
    /// behind, so a scrub back is answered from the phone.
    public mutating func window(atSeconds seconds: Double, bytesPerSecond: Double,
                                fileBytes: Int64) -> AudioByteRange? {
        guard fileBytes > 0, bytesPerSecond > 0 else { return nil }
        let playhead = Self.byteOffset(seconds: seconds, bytesPerSecond: bytesPerSecond,
                                       fileBytes: fileBytes)
        if let asked, asked.offset <= playhead, asked.end - playhead > asked.count / 2 { return nil }
        let wanted = AudioByteRange(offset: playhead, count: min(leadBytes, fileBytes - playhead))
        asked = wanted
        return wanted
    }

    /// The ask that lets a song start: the head, and for a file whose container may hide its metadata
    /// at the end, the tail too.
    public static func head(for fileBytes: Int64, includingTail: Bool) -> [AudioByteRange] {
        guard fileBytes > 0 else { return [] }
        var windows = [AudioByteRange(offset: 0, count: min(headBytes, fileBytes))]
        if includingTail, fileBytes > headBytes * 2 {
            let tail = min(tailBytes, fileBytes - headBytes)
            windows.append(AudioByteRange(offset: fileBytes - tail, count: tail))
        }
        return windows
    }

    /// The window the *next* song is worth holding in reserve: its head and nothing more. A prefetch
    /// that pulls a whole file is the download manager this replaced.
    public static func prefetch(for fileBytes: Int64) -> AudioByteRange {
        AudioByteRange(offset: 0, count: min(headBytes, max(0, fileBytes)))
    }

    /// The buffer ran out. Buy twice as far ahead next time, to the ceiling.
    public mutating func noteRebuffer() {
        leadBytes = min(Self.maximumLeadBytes, max(leadBytes * 2, Self.minimumLeadBytes))
        // A window that has already failed to cover the playhead must not be trusted to still cover it.
        asked = nil
    }

    /// The buffer was comfortable, so stop buying so far ahead. Halved only once the lead has more
    /// than doubled what it needs, which keeps a single good moment from shrinking the whole plan.
    public mutating func noteComfortable(aheadBytes: Int64) {
        guard aheadBytes > leadBytes * 2, leadBytes > Self.minimumLeadBytes else { return }
        leadBytes = max(Self.minimumLeadBytes, leadBytes / 2)
    }

    /// Forget the window last asked for, so the next plan is asked again with the playhead unmoved —
    /// which is exactly a retry after a stopped download.
    public mutating func forgetAsked() {
        asked = nil
    }
}
