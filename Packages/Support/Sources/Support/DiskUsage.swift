import Foundation

/// Byte counting for a storage screen, on the reference's rules
/// (`StorageMaintenance.swift:203-253`, `:179-199`).
///
/// Allocated size rather than logical size, because allocated is what the system charges an app for
/// in its own Settings panel — and the reason this exists is that the numbers the library kept in its
/// rows had stopped agreeing with that panel.
public enum DiskUsage {
    /// Everything a path holds, in allocated bytes: a file's own size, or every regular file under a
    /// directory. A path that is not there is nothing rather than a failure, which is what a first
    /// launch looks like.
    public static func bytes(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        if let size = allocated(of: url) { return size }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += allocated(of: fileURL) ?? 0
        }
        return total
    }

    /// Throwing away a file or a whole directory, and saying how many bytes that got back. Zero when
    /// anything is left, so a screen can promise room only when it really made room.
    @discardableResult
    public static func clear(_ url: URL, fileManager: FileManager = .default) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let freed = bytes(at: url, fileManager: fileManager)
        try? fileManager.removeItem(at: url)
        return fileManager.fileExists(atPath: url.path) ? 0 : freed
    }

    /// The volume this app lives on: its capacity and what is free. Either is `nil` when the system
    /// will not say, which is the signal to draw no bar at all rather than an empty one.
    public static func deviceCapacity() -> (total: Int64?, available: Int64?) {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        )
        return (values?.volumeTotalCapacity.map(Int64.init),
                values?.volumeAvailableCapacityForImportantUsage)
    }

    private static let keys: Set<URLResourceKey> = [
        .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .totalFileAllocatedSizeKey
    ]

    /// The one answer that means "this is a file, and it weighs this". A directory answers nil, which
    /// is what sends the caller on to its children.
    private static func allocated(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true else { return nil }
        return Int64(values.totalFileAllocatedSize
            ?? values.fileAllocatedSize
            ?? values.fileSize ?? 0)
    }
}
