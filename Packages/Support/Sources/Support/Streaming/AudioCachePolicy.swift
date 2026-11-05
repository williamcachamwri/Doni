import Foundation

/// One song's claim on the disk, in the terms a quota has to be argued in.
public struct AudioCacheRow: Sendable, Equatable {
    public let uniqueId: String
    /// What it occupies now: the whole file when it is complete, the ready parts when it is not.
    public let bytes: Int64
    public let isComplete: Bool
    /// When the user last listened. `nil` is a song that was fetched and never played, which is the
    /// first thing to go, not the last.
    public let lastPlayedAt: Date?
    /// The song under the playhead. TDLib has no partial delete — `deleteFile` gives up the whole
    /// file (`td_api.tl:15051`) — so a song being streamed right now cannot be a victim of a sweep.
    public let isCurrent: Bool

    public init(uniqueId: String, bytes: Int64, isComplete: Bool,
                lastPlayedAt: Date?, isCurrent: Bool = false) {
        self.uniqueId = uniqueId
        self.bytes = max(0, bytes)
        self.isComplete = isComplete
        self.lastPlayedAt = lastPlayedAt
        self.isCurrent = isCurrent
    }
}

/// Which songs the disk has to give back.
///
/// Eviction is whole-file because that is the only granularity TDLib offers, which makes this a
/// choice about *people*, not about bytes — and the order it chooses in is recency, not completeness.
/// A half-downloaded song is worth exactly as much as a whole one to a listener who is about to play
/// it, because the missing parts come from the network while the song is already playing; deleting
/// the song that is 90 % there to keep one that was fetched and never opened is how a cache built on
/// "prefer complete files" throws away the work that mattered.
///
/// Inside one moment of equal recency the half file does go first, and a sweep of the same library
/// always names the same victims.
public enum AudioCachePolicy {
    public static func evictions(_ rows: [AudioCacheRow], quotaBytes: Int64) -> [String] {
        let total = rows.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > quotaBytes else { return [] }

        var freed: Int64 = 0
        var victims: [String] = []
        for row in ranked(rows) {
            victims.append(row.uniqueId)
            freed += row.bytes
            if total - freed <= quotaBytes { break }
        }
        return victims
    }

    /// Worst to keep first: never the song under the playhead, then the never-opened before the
    /// opened, then the oldest listen.
    public static func ranked(_ rows: [AudioCacheRow]) -> [AudioCacheRow] {
        rows.filter { !$0.isCurrent }.sorted { left, right in
            switch (left.lastPlayedAt, right.lastPlayedAt) {
            case let (a?, b?):
                if a != b { return a < b }
            case (nil, .some): return true
            case (.some, nil): return false
            case (nil, nil): break
            }
            if left.isComplete != right.isComplete { return !left.isComplete }
            return left.uniqueId < right.uniqueId
        }
    }
}
