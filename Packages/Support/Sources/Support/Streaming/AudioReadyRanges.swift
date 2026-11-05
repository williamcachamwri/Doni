import Foundation

/// A stretch of one file, in bytes, named the way a reader has to name it: from where, and how much.
///
/// Offsets are absolute and `count` is never negative, so "the empty range" is `count == 0` rather
/// than a second shape a caller has to remember to check.
public struct AudioByteRange: Hashable, Sendable {
    public let offset: Int64
    public let count: Int64

    public init(offset: Int64, count: Int64) {
        self.offset = max(0, offset)
        self.count = max(0, count)
    }

    /// One past the last byte in the range, which is what a window's end is compared against.
    public var end: Int64 { offset + count }

    public var isEmpty: Bool { count == 0 }

    /// Whether the two touch or overlap. Touching counts: two ranges that meet are one stretch of
    /// bytes, and a set that kept them apart would report a hole where there is none.
    public func touches(_ other: AudioByteRange) -> Bool {
        offset <= other.end && other.offset <= end
    }
}

/// The parts of a file that are on the device and mean what they say.
///
/// TDLib downloads in 64 KiB parts (`PartsManager.cpp:132`) written at their own offset
/// (`FileDownloader.cpp:281`), so a song's file on the phone is a patchwork: real bytes here, garbage
/// there, and no order between them. This is the shape of that patchwork, kept here rather than read
/// out of TDLib every time a byte is wanted, and merged on the way in so a long listen over a hundred
/// part-boundaries stays a handful of ranges.
public struct AudioReadyRanges: Sendable {
    /// Sorted, disjoint, and never touching each other — the invariant `mark` maintains.
    public private(set) var spans: [AudioByteRange] = []

    public init() {}

    public init(_ spans: [AudioByteRange]) {
        for span in spans { mark(span) }
    }

    /// The bytes the player may read starting exactly at `offset`.
    ///
    /// It starts at `offset` and stops at the first hole, because a read that runs into a hole hands
    /// back bytes that are the neighbouring part's, and a decoder that plays them is a song that
    /// glitches at a point that moves with the network.
    public func contiguous(at offset: Int64) -> Int64 {
        for span in spans where span.offset <= offset && offset < span.end {
            return span.end - offset
        }
        return 0
    }

    public var totalBytes: Int64 { spans.reduce(0) { $0 + $1.count } }

    /// Where the first hole is before `end`, which is what a "fill the file in" ask is pointed at.
    public func firstGap(before end: Int64) -> Int64? {
        var walked: Int64 = 0
        for span in spans {
            if span.offset >= end { break }
            if span.offset > walked { return walked }
            walked = max(walked, min(span.end, end))
        }
        return walked < end ? walked : nil
    }

    public mutating func mark(_ range: AudioByteRange) {
        guard !range.isEmpty else { return }
        // Everything the new range touches is folded into it: one pass over a sorted list is cheaper
        // than the caller learning to merge by hand, and a caller that forgets to is a set of ranges
        // with a hole in it that reads as "not downloaded".
        var merged = range
        var kept: [AudioByteRange] = []
        for span in spans {
            if span.touches(merged) {
                merged = AudioByteRange(offset: min(span.offset, merged.offset),
                                        count: max(span.end, merged.end) - min(span.offset, merged.offset))
            } else {
                kept.append(span)
            }
        }
        kept.append(merged)
        spans = kept.sorted { $0.offset < $1.offset }
    }

    /// What a caller that has just read `count` bytes at `offset` should record.
    ///
    /// A short read is the normal answer at the end of a file, and marking only what actually came
    /// back is what keeps the index honest about the last few kilobytes.
    public mutating func markRead(_ range: AudioByteRange, returned: Int) {
        mark(AudioByteRange(offset: range.offset, count: Int64(max(0, returned))))
    }
}
