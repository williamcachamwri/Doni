import Foundation
import Support

/// What Doni holds on the phone, counted off the disk in allocated bytes, the way the system counts
/// (`DiskUsage`). The library's row-based total and TDLib's real directory drift apart in both
/// directions — TDLib fetches on stream, keeps files the rows never marked, and prunes its own
/// directory when the phone wants room — and it is the disk iOS charges the app for in Settings.
struct DoniStorage: Equatable, Sendable {
    /// TDLib's directory: the songs it fetched, the pictures it thumbed, what it left in temp — the bulk
    /// of this app on a phone that has been listening.
    var telegramBytes: Int64
    /// Files the user brought in themselves — the one thing here no server can hand back.
    var importedBytes: Int64
    /// Cached covers and channel photos: every picture this app can get back on its own.
    var pictureBytes: Int64
    /// This app's own records: its SQLite file and the picture a user chose for a list — the half a
    /// cleanup must not touch.
    var libraryBytes: Int64
    /// TDLib's working area: database, binary log, its own sticker and photo folders. Not the user's
    /// library — a fresh engine still spends several megabytes here and grows again at sign-in. Its own
    /// row because merging it with the library made a clean sign-out look like a failed one.
    var engineBytes: Int64
    var deviceTotalBytes: Int64?
    var deviceFreeBytes: Int64?

    /// Everything the app owns, which is what the system's storage panel calls "Documents & Data".
    var managedBytes: Int64 {
        telegramBytes + importedBytes + pictureBytes + libraryBytes + engineBytes
    }

    /// What can be thrown away and come back on its own: what Telegram can send again and what decodes
    /// out of the files already here. Imported songs and records are excluded — losing those is deleting.
    var reclaimableBytes: Int64 { telegramBytes + pictureBytes }

    var deviceUsedBytes: Int64? {
        guard let total = deviceTotalBytes, let free = deviceFreeBytes, total > 0 else { return nil }
        return max(total - free, 0)
    }
}

/// Measuring, and the two cleanups the storage screen offers.
enum StorageTally {
    /// Every directory walked. Off the main thread at utility priority: this is a few thousand stat
    /// calls, and a settings screen is not worth a dropped frame — nor a phone-wide file lock.
    static func measure() async -> DoniStorage {
        await Task.detached(priority: .utility) {
            let capacity = DiskUsage.deviceCapacity()
            return DoniStorage(
                telegramBytes: DiskUsage.bytes(at: TelegramSession.filesDirectory),
                importedBytes: DiskUsage.bytes(at: Library.musicDirectory),
                pictureBytes: DiskUsage.bytes(at: CoverArtwork.sourceDirectory)
                    + DiskUsage.bytes(at: Library.avatarDirectory),
                libraryBytes: StorageTally.libraryDatabaseBytes()
                    + DiskUsage.bytes(at: Library.coverDirectory),
                engineBytes: DiskUsage.bytes(at: TelegramSession.databaseDirectory),
                deviceTotalBytes: capacity.total,
                deviceFreeBytes: capacity.available
            )
        }.value
    }

    /// Releasing the pictures: decoded tiles in memory, cover bytes on disk, channel photos. A row redraws
    /// what it needs when it is next looked at and a song's art re-reads from its file, which is what makes
    /// this safe to offer as a button. Not here: the picture a user chose for a list — the only copy of it
    /// is the file this app wrote.
    @MainActor
    static func clearPictures(_ artwork: CoverArtwork) -> Int64 {
        artwork.clearCache() + DiskUsage.clear(Library.avatarDirectory)
    }

    /// The library's three files, named rather than walked: their directory also holds songs and pictures,
    /// counted on their own rows.
    private nonisolated static func libraryDatabaseBytes() -> Int64 {
        ["library.db", "library.db-wal", "library.db-shm"].reduce(Int64(0)) { total, name in
            total + DiskUsage.bytes(at: Library.supportDirectory.appendingPathComponent(name))
        }
    }
}
