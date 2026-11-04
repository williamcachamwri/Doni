import Foundation
import Support

/// What Doni holds on the phone, counted off the disk.
///
/// This exists because two numbers had stopped agreeing. The library's own total adds up the sizes
/// written in its rows — a report of what the app meant to keep — while TDLib fetches a song the
/// moment it is streamed, keeps files the rows never marked, and prunes its own directory when the
/// phone wants room back. The two drift apart in both directions, and it is the disk that iOS
/// charges the app for in its own Settings. So every number here is measured, in allocated bytes,
/// the same way the system counts (`DiskUsage`).
struct DoniStorage: Equatable, Sendable {
    /// TDLib's directory: the songs it fetched, the pictures it thumbed, and what it left in temp.
    /// The bulk of this app on a phone that has been listening.
    var telegramBytes: Int64
    /// Files the user brought in themselves — the one thing here no server can hand back.
    var importedBytes: Int64
    /// Cached covers and channel photos: every picture this app can get back on its own.
    var pictureBytes: Int64
    /// This app's SQLite file and TDLib's database, plus the list covers a user chose — the records
    /// half, which is what a cleanup must not touch.
    var recordsBytes: Int64
    var deviceTotalBytes: Int64?
    var deviceFreeBytes: Int64?

    /// Everything the app owns, which is what the system's storage panel calls "Documents & Data".
    var managedBytes: Int64 { telegramBytes + importedBytes + pictureBytes + recordsBytes }

    /// The part that can be thrown away and come back on its own: what Telegram can send again, and
    /// what can be decoded out of the files already here. Imported songs and the records are not in
    /// it, because losing those is not cleaning, it is deleting.
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
                recordsBytes: StorageTally.libraryDatabaseBytes()
                    + DiskUsage.bytes(at: TelegramSession.databaseDirectory)
                    + DiskUsage.bytes(at: Library.coverDirectory),
                deviceTotalBytes: capacity.total,
                deviceFreeBytes: capacity.available
            )
        }.value
    }

    /// Releasing the pictures: the decoded tiles in memory, the cover bytes on disk, and the channel
    /// photos. A row redraws what it needs the next time it is looked at, and a song's own art is
    /// read out of its file again — which is what makes this safe to offer as a button.
    ///
    /// Not in here: the picture a user chose for a list. It came out of their own photo library and
    /// the only copy of it is the file this app wrote, so the screen leaves it where it is.
    @MainActor
    static func clearPictures(_ artwork: CoverArtwork) -> Int64 {
        artwork.clearCache() + DiskUsage.clear(Library.avatarDirectory)
    }

    /// The library's three files, named rather than walked: the directory they sit in also holds the
    /// songs and the pictures, and those are counted on their own rows.
    private nonisolated static func libraryDatabaseBytes() -> Int64 {
        ["library.db", "library.db-wal", "library.db-shm"].reduce(Int64(0)) { total, name in
            total + DiskUsage.bytes(at: Library.supportDirectory.appendingPathComponent(name))
        }
    }
}
