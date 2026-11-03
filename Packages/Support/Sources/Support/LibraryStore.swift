import Foundation
import SQLite3

/// A music channel the app has been pointed at.
public struct StoreChannel: Equatable, Sendable, Identifiable {
    public var id: Int64 { chatId }
    public var chatId: Int64
    public var username: String
    public var title: String
    /// Whether Doni reads this channel — more than one can be added, one is the current one.
    public var isSelected: Bool

    public init(chatId: Int64, username: String, title: String, isSelected: Bool = false) {
        self.chatId = chatId
        self.username = username
        self.title = title
        self.isSelected = isSelected
    }
}

/// A playable message, written down.
///
/// This is a snapshot rather than a live `TdTrack`: a favourite or a playlist entry has to survive
/// the channel being re-read, and `file:id:int32` (`td_api.tl:326`) is per-database anyway, so the
/// only key that identifies the same song twice is MTProto's `unique_id`.
public struct StoreTrack: Equatable, Sendable, Identifiable {
    public var id: String { uniqueId }
    public var uniqueId: String
    public var chatId: Int64
    public var messageId: Int64
    public var fileId: Int
    public var coverFileId: Int?
    public var title: String
    public var performer: String
    public var fileName: String
    public var duration: Int?
    public var size: Int64
    public var date: Int64
    public var localPath: String?
    public var miniArtwork: Data?

    public init(uniqueId: String, chatId: Int64, messageId: Int64, fileId: Int,
                coverFileId: Int? = nil, title: String, performer: String, fileName: String,
                duration: Int?, size: Int64, date: Int64, localPath: String? = nil,
                miniArtwork: Data? = nil) {
        self.uniqueId = uniqueId
        self.chatId = chatId
        self.messageId = messageId
        self.fileId = fileId
        self.coverFileId = coverFileId
        self.title = title
        self.performer = performer
        self.fileName = fileName
        self.duration = duration
        self.size = size
        self.date = date
        self.localPath = localPath
        self.miniArtwork = miniArtwork
    }
}

/// A list the user made.
public struct StoredPlaylist: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var name: String
    public var createdAt: Int64
    public var trackCount: Int

    public init(id: Int64, name: String, createdAt: Int64, trackCount: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.trackCount = trackCount
    }
}

/// A song the user kept, optionally only a slice of it.
public struct StoredFavorite: Equatable, Sendable, Identifiable {
    public var id: String { track.uniqueId }
    public var track: StoreTrack
    /// `nil` means the whole song. Both are seconds, and a slice is what makes this app's
    /// favourite different from a bookmark.
    public var start: Int?
    public var end: Int?
    public var createdAt: Int64

    public init(track: StoreTrack, start: Int?, end: Int?, createdAt: Int64) {
        self.track = track
        self.start = start
        self.end = end
        self.createdAt = createdAt
    }

    public var segment: ClosedRange<Int>? {
        guard let start, let end, end > start else { return nil }
        return start...end
    }
}

/// The app's own database, in SQLite.
///
/// Hand-rolled rather than a wrapper: the schema is five tables, and a library that has to hold
/// 50 000 rows and answer "which of these are already on the phone" should not carry an ORM.
/// Everything is one class with one lock, because the app only ever writes from the index walk
/// and from a tap, both of which are already serialised on the main actor.
public final class LibraryStore: @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case cannotOpen(String)
        case statement(String)
    }

    /// `1` is the first schema; a column added later bumps this and the row below it migrates.
    private static let schemaVersion = 1

    private let lock = NSLock()
    private var handle: OpaquePointer?

    /// Opens (and creates if needed) the database at `path`.
    public init(path: String) {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let opened {
            handle = opened
            sqlite3_busy_timeout(opened, 2000)
            Self.configure(opened)
            Self.createSchema(opened)
        } else {
            handle = nil
        }
    }

    deinit {
        close()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if let handle { sqlite3_close_v2(handle) }
        handle = nil
    }

    private static func configure(_ handle: OpaquePointer) {
        sqlRun(handle, "PRAGMA journal_mode = WAL")
        sqlRun(handle, "PRAGMA foreign_keys = ON")
    }

    private static func createSchema(_ handle: OpaquePointer) {
        sqlRun(handle, """
        CREATE TABLE IF NOT EXISTS channel (
            chat_id INTEGER PRIMARY KEY,
            username TEXT NOT NULL,
            title TEXT NOT NULL,
            is_selected INTEGER NOT NULL DEFAULT 0
        )
        """)
        sqlRun(handle, """
        CREATE TABLE IF NOT EXISTS track (
            unique_id TEXT PRIMARY KEY,
            chat_id INTEGER NOT NULL,
            message_id INTEGER NOT NULL,
            file_id INTEGER NOT NULL,
            cover_file_id INTEGER,
            title TEXT NOT NULL,
            performer TEXT NOT NULL,
            file_name TEXT NOT NULL,
            duration INTEGER,
            size INTEGER NOT NULL,
            date INTEGER NOT NULL,
            local_path TEXT,
            mini_artwork BLOB
        )
        """)
        sqlRun(handle, "CREATE INDEX IF NOT EXISTS track_chat ON track (chat_id, date DESC)")
        sqlRun(handle, """
        CREATE TABLE IF NOT EXISTS favorite (
            unique_id TEXT PRIMARY KEY,
            start_seconds INTEGER,
            end_seconds INTEGER,
            created_at INTEGER NOT NULL
        )
        """)
        sqlRun(handle, """
        CREATE TABLE IF NOT EXISTS playlist (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL
        )
        """)
        sqlRun(handle, """
        CREATE TABLE IF NOT EXISTS playlist_track (
            playlist_id INTEGER NOT NULL,
            unique_id TEXT NOT NULL,
            position INTEGER NOT NULL,
            added_at INTEGER NOT NULL,
            PRIMARY KEY (playlist_id, unique_id),
            FOREIGN KEY (playlist_id) REFERENCES playlist (id) ON DELETE CASCADE
        )
        """)
        sqlRun(handle, "PRAGMA user_version = \(Self.schemaVersion)")
    }

    // MARK: Channels

    public func channels() -> [StoreChannel] {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT chat_id, username, title, is_selected FROM channel"
            + " ORDER BY title COLLATE NOCASE"
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [StoreChannel] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(StoreChannel(
                chatId: sqlite3_column_int64(statement, 0),
                username: Self.text(statement, 1),
                title: Self.text(statement, 2),
                isSelected: sqlite3_column_int(statement, 3) != 0
            ))
        }
        return rows
    }

    /// Remembers a channel. Reading it is the app's business, not the row's.
    @discardableResult
    public func save(channel: StoreChannel) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            INSERT INTO channel (chat_id, username, title, is_selected) VALUES (?, ?, ?, ?)
            ON CONFLICT (chat_id) DO UPDATE
            SET username = excluded.username, title = excluded.title
            """) else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, channel.chatId)
        sqlite3_bind_text(statement, 2, channel.username, -1, Self.transient)
        sqlite3_bind_text(statement, 3, channel.title, -1, Self.transient)
        sqlite3_bind_int(statement, 4, channel.isSelected ? 1 : 0)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// The one channel the home list reads. Exactly one row can hold this.
    public func setSelectedChannel(chatId: Int64) {
        lock.lock()
        defer { lock.unlock() }
        sqlRun(handle, "UPDATE channel SET is_selected = 0")
        guard let statement = prepare("UPDATE channel SET is_selected = 1 WHERE chat_id = ?")
        else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, chatId)
        sqlite3_step(statement)
    }

    public func selectedChannel() -> StoreChannel? {
        channels().first { $0.isSelected }
    }

    public func removeChannel(chatId: Int64) {
        lock.lock()
        defer { lock.unlock() }
        // The songs go with it, and so does anything that pointed at them: a heart on a track
        // nobody can reach is a row that will never play again.
        sqlRun(handle, "BEGIN")
        let owned = "(SELECT unique_id FROM track WHERE chat_id = \(chatId))"
        sqlRun(handle, "DELETE FROM favorite WHERE unique_id IN \(owned)")
        sqlRun(handle, "DELETE FROM playlist_track WHERE unique_id IN \(owned)")
        sqlRun(handle, "DELETE FROM track WHERE chat_id = \(chatId)")
        sqlRun(handle, "DELETE FROM channel WHERE chat_id = \(chatId)")
        sqlRun(handle, "COMMIT")
    }

    // MARK: Tracks

    /// Writes a page of the library. A song the page re-states keeps the path already recorded
    /// on the phone, because the write is an upsert; a song the page no longer mentions is
    /// retired, since the channel does not carry it any more.
    public func replaceTracks(chatId: Int64, tracks: [StoreTrack]) {
        lock.lock()
        defer { lock.unlock() }
        sqlRun(handle, "BEGIN")
        // The rows are written under the channel they are being replaced for, so a page that
        // carries the wrong `chat_id` cannot leave a song behind that no channel can reach.
        for track in tracks {
            var owned = track
            owned.chatId = chatId
            insert(track: owned)
        }
        pruneTracks(chatId: chatId, keeping: tracks.map { $0.uniqueId })
        sqlRun(handle, "COMMIT")
    }

    /// A walk writes page by page, newest first, so pages overlap. The write underneath is an
    /// upsert, which is what lets an overlap update a row without forgetting where its file is.
    public func appendTracks(_ tracks: [StoreTrack]) {
        lock.lock()
        defer { lock.unlock() }
        sqlRun(handle, "BEGIN")
        for track in tracks { insert(track: track) }
        sqlRun(handle, "COMMIT")
    }

    public func tracks(chatId: Int64? = nil) -> [StoreTrack] {
        lock.lock()
        defer { lock.unlock() }
        let sql = chatId == nil
            ? "SELECT \(Self.columns) FROM track ORDER BY date DESC, message_id DESC"
            : "SELECT \(Self.columns) FROM track WHERE chat_id = ? ORDER BY date DESC, message_id DESC"
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        if let chatId { sqlite3_bind_int64(statement, 1, chatId) }
        var rows: [StoreTrack] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(Self.read(statement)) }
        return rows
    }

    public func track(uniqueId: String) -> StoreTrack? {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("SELECT \(Self.columns) FROM track WHERE unique_id = ?")
        else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uniqueId, -1, Self.transient)
        return sqlite3_step(statement) == SQLITE_ROW ? Self.read(statement) : nil
    }

    /// Where TDLib put the file, so a song that is already downloaded never asks again.
    public func setLocalPath(_ path: String?, uniqueId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("UPDATE track SET local_path = ? WHERE unique_id = ?")
        else { return }
        defer { sqlite3_finalize(statement) }
        if let path {
            sqlite3_bind_text(statement, 1, path, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, 1)
        }
        sqlite3_bind_text(statement, 2, uniqueId, -1, Self.transient)
        sqlite3_step(statement)
    }

    private func deleteTracks(chatId: Int64) {
        guard let statement = prepare("DELETE FROM track WHERE chat_id = ?") else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, chatId)
        sqlite3_step(statement)
    }

    /// Retires the rows a page did not mention. The list is bound as parameters, not spliced into
    /// the SQL, so a unique id is never an injection point.
    private func pruneTracks(chatId: Int64, keeping uniqueIds: [String]) {
        guard !uniqueIds.isEmpty else {
            deleteTracks(chatId: chatId)
            return
        }
        let marks = repeatElement("?", count: uniqueIds.count).joined(separator: ", ")
        guard let statement = prepare(
            "DELETE FROM track WHERE chat_id = ? AND unique_id NOT IN (\(marks))") else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, chatId)
        // Index 1 is the channel, so the list starts at 2 — bound onto 1 would overwrite it and
        // leave a NULL in the last slot, which makes `NOT IN` match nothing at all.
        for (offset, key) in uniqueIds.enumerated() {
            sqlite3_bind_text(statement, Int32(2 + offset), key, -1, Self.transient)
        }
        sqlite3_step(statement)
    }

    private func insert(track: StoreTrack) {
        guard let statement = prepare("""
            INSERT INTO track (\(Self.columns))
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(unique_id) DO UPDATE SET
                chat_id = excluded.chat_id,
                message_id = excluded.message_id,
                file_id = excluded.file_id,
                cover_file_id = COALESCE(excluded.cover_file_id, track.cover_file_id),
                title = excluded.title,
                performer = excluded.performer,
                file_name = excluded.file_name,
                duration = COALESCE(excluded.duration, track.duration),
                size = excluded.size,
                date = excluded.date,
                local_path = COALESCE(excluded.local_path, track.local_path),
                mini_artwork = COALESCE(excluded.mini_artwork, track.mini_artwork)
            """) else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, track.uniqueId, -1, Self.transient)
        sqlite3_bind_int64(statement, 2, track.chatId)
        sqlite3_bind_int64(statement, 3, track.messageId)
        sqlite3_bind_int(statement, 4, Int32(track.fileId))
        if let cover = track.coverFileId {
            sqlite3_bind_int(statement, 5, Int32(cover))
        } else {
            sqlite3_bind_null(statement, 5)
        }
        sqlite3_bind_text(statement, 6, track.title, -1, Self.transient)
        sqlite3_bind_text(statement, 7, track.performer, -1, Self.transient)
        sqlite3_bind_text(statement, 8, track.fileName, -1, Self.transient)
        if let duration = track.duration {
            sqlite3_bind_int(statement, 9, Int32(duration))
        } else {
            sqlite3_bind_null(statement, 9)
        }
        sqlite3_bind_int64(statement, 10, track.size)
        sqlite3_bind_int64(statement, 11, track.date)
        if let path = track.localPath {
            sqlite3_bind_text(statement, 12, path, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, 12)
        }
        if let artwork = track.miniArtwork {
            _ = artwork.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, 13, buffer.baseAddress, Int32(buffer.count),
                                  Self.transient)
            }
        } else {
            sqlite3_bind_null(statement, 13)
        }
        sqlite3_step(statement)
    }

    // MARK: Favourites

    /// Keeps a song, or the slice of it the user was listening to. Tapping the same heart again
    /// takes it away. Returns whether it is now a favourite.
    @discardableResult
    public func toggleFavorite(uniqueId: String, segment: ClosedRange<Int>?,
                               at now: Int64 = Int64(Date().timeIntervalSince1970)) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isFavoriteLocked(uniqueId) {
            removeFavoriteLocked(uniqueId)
            return false
        }
        guard let statement = prepare("""
            INSERT INTO favorite (unique_id, start_seconds, end_seconds, created_at) VALUES (?, ?, ?, ?)
            """) else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uniqueId, -1, Self.transient)
        if let segment {
            sqlite3_bind_int(statement, 2, Int32(segment.lowerBound))
            sqlite3_bind_int(statement, 3, Int32(segment.upperBound))
        } else {
            sqlite3_bind_null(statement, 2)
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_int64(statement, 4, now)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    public func isFavorite(_ uniqueId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFavoriteLocked(uniqueId)
    }

    /// The slice a heart holds for this song, `nil` when the whole song is kept.
    public func favoriteSegment(_ uniqueId: String) -> ClosedRange<Int>? {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            SELECT start_seconds, end_seconds FROM favorite WHERE unique_id = ?
            """) else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uniqueId, -1, Self.transient)
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) != SQLITE_NULL,
              sqlite3_column_type(statement, 1) != SQLITE_NULL
        else { return nil }
        let start = Int(sqlite3_column_int(statement, 0))
        let end = Int(sqlite3_column_int(statement, 1))
        guard end > start else { return nil }
        return start...end
    }

    public func favorites() -> [StoredFavorite] {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            SELECT f.start_seconds, f.end_seconds, f.created_at, \(Self.aliasedColumns)
            FROM favorite f JOIN track t ON t.unique_id = f.unique_id
            ORDER BY f.created_at DESC
            """) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [StoredFavorite] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            // The favourite's own three columns come first, then the track's thirteen.
            let start = sqlite3_column_type(statement, 0) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int(statement, 0))
            let end = sqlite3_column_type(statement, 1) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int(statement, 1))
            let created = sqlite3_column_int64(statement, 2)
            let track = Self.read(statement, offset: 3)
            rows.append(StoredFavorite(track: track, start: start, end: end, createdAt: created))
        }
        return rows
    }

    public func removeFavorite(_ uniqueId: String) {
        lock.lock()
        defer { lock.unlock() }
        removeFavoriteLocked(uniqueId)
    }

    /// Writing a slice onto a favourite that already exists — the "chọn đoạn này" button on a
    /// song that was already loved whole.
    @discardableResult
    public func setFavoriteSegment(_ segment: ClosedRange<Int>?, uniqueId: String,
                                   at now: Int64 = Int64(Date().timeIntervalSince1970)) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            INSERT INTO favorite (unique_id, start_seconds, end_seconds, created_at) VALUES (?, ?, ?, ?)
            ON CONFLICT (unique_id) DO UPDATE
            SET start_seconds = excluded.start_seconds, end_seconds = excluded.end_seconds
            """) else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uniqueId, -1, Self.transient)
        if let segment {
            sqlite3_bind_int(statement, 2, Int32(segment.lowerBound))
            sqlite3_bind_int(statement, 3, Int32(segment.upperBound))
        } else {
            sqlite3_bind_null(statement, 2)
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_int64(statement, 4, now)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func isFavoriteLocked(_ uniqueId: String) -> Bool {
        guard let statement = prepare("SELECT 1 FROM favorite WHERE unique_id = ?") else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uniqueId, -1, Self.transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func removeFavoriteLocked(_ uniqueId: String) {
        guard let statement = prepare("DELETE FROM favorite WHERE unique_id = ?") else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uniqueId, -1, Self.transient)
        sqlite3_step(statement)
    }

    // MARK: Playlists

    /// Names are unique, so a duplicate comes back as `nil` and the screen says so.
    public func createPlaylist(name: String,
                               at now: Int64 = Int64(Date().timeIntervalSince1970)) -> StoredPlaylist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            INSERT INTO playlist (name, created_at) VALUES (?, ?)
            """) else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, trimmed, -1, Self.transient)
        sqlite3_bind_int64(statement, 2, now)
        guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
        return StoredPlaylist(id: sqlite3_last_insert_rowid(handle), name: trimmed,
                              createdAt: now, trackCount: 0)
    }

    public func renamePlaylist(id: Int64, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("UPDATE playlist SET name = ? WHERE id = ?") else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, trimmed, -1, Self.transient)
        sqlite3_bind_int64(statement, 2, id)
        return sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(handle) > 0
    }

    public func deletePlaylist(id: Int64) {
        lock.lock()
        defer { lock.unlock() }
        sqlRun(handle, "BEGIN")
        if let statement = prepare("DELETE FROM playlist_track WHERE playlist_id = ?") {
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        if let statement = prepare("DELETE FROM playlist WHERE id = ?") {
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        sqlRun(handle, "COMMIT")
    }

    public func playlists() -> [StoredPlaylist] {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            SELECT p.id, p.name, p.created_at,
                   (SELECT COUNT(*) FROM playlist_track pt WHERE pt.playlist_id = p.id)
            FROM playlist p ORDER BY p.created_at
            """) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [StoredPlaylist] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(StoredPlaylist(
                id: sqlite3_column_int64(statement, 0),
                name: Self.text(statement, 1),
                createdAt: sqlite3_column_int64(statement, 2),
                trackCount: Int(sqlite3_column_int(statement, 3))
            ))
        }
        return rows
    }

    /// Adding the same song twice is a no-op, so a row's sheet can be tapped twice without the
    /// playlist growing a duplicate. Returns false when it was already there.
    @discardableResult
    public func add(track: StoreTrack, to playlistId: Int64,
                    at now: Int64 = Int64(Date().timeIntervalSince1970)) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        insert(track: track)
        guard let statement = prepare("""
            INSERT INTO playlist_track (playlist_id, unique_id, position, added_at)
            VALUES (?, ?, (SELECT COALESCE(MAX(position), 0) + 1 FROM playlist_track
                           WHERE playlist_id = ?), ?)
            ON CONFLICT (playlist_id, unique_id) DO NOTHING
            """) else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, playlistId)
        sqlite3_bind_text(statement, 2, track.uniqueId, -1, Self.transient)
        sqlite3_bind_int64(statement, 3, playlistId)
        sqlite3_bind_int64(statement, 4, now)
        guard sqlite3_step(statement) == SQLITE_DONE else { return false }
        return sqlite3_changes(handle) > 0
    }

    public func removeTrack(uniqueId: String, from playlistId: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            DELETE FROM playlist_track WHERE playlist_id = ? AND unique_id = ?
            """) else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, playlistId)
        sqlite3_bind_text(statement, 2, uniqueId, -1, Self.transient)
        sqlite3_step(statement)
    }

    public func playlists(containing uniqueId: String) -> [Int64] {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            SELECT playlist_id FROM playlist_track WHERE unique_id = ? ORDER BY playlist_id
            """) else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uniqueId, -1, Self.transient)
        var ids: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(statement, 0))
        }
        return ids
    }

    /// In the order the user put them in, not the order they were posted.
    public func playlistTracks(playlistId: Int64) -> [StoreTrack] {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            SELECT \(Self.aliasedColumns)
            FROM playlist_track pt JOIN track t ON t.unique_id = pt.unique_id
            WHERE pt.playlist_id = ?
            ORDER BY pt.position
            """) else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, playlistId)
        var rows: [StoreTrack] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(Self.read(statement)) }
        return rows
    }

    // MARK: Downloads

    /// Songs whose file is on the phone — what Settings quotes as the offline count.
    public func downloadedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("SELECT COUNT(*) FROM track WHERE local_path IS NOT NULL")
        else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    public func trackCount(chatId: Int64? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let sql = chatId == nil
            ? "SELECT COUNT(*) FROM track"
            : "SELECT COUNT(*) FROM track WHERE chat_id = ?"
        guard let statement = prepare(sql) else { return 0 }
        defer { sqlite3_finalize(statement) }
        if let chatId { sqlite3_bind_int64(statement, 1, chatId) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    /// Everything on the phone that this app put there: the library rows, the hearts, the lists.
    /// A logout wipes the cache, and the brief says the session is the only thing Keychain keeps.
    public func wipeLibrary() {
        lock.lock()
        defer { lock.unlock() }
        sqlRun(handle, "BEGIN")
        for table in ["playlist_track", "playlist", "favorite", "track", "channel"] {
            sqlRun(handle, "DELETE FROM \(table)")
        }
        sqlRun(handle, "COMMIT")
    }

    // MARK: Plumbing

    private static let columns = """
    unique_id, chat_id, message_id, file_id, cover_file_id, title, performer, file_name, \
    duration, size, date, local_path, mini_artwork
    """

    private static let aliasedColumns = """
    t.unique_id, t.chat_id, t.message_id, t.file_id, t.cover_file_id, t.title, t.performer, \
    t.file_name, t.duration, t.size, t.date, t.local_path, t.mini_artwork
    """

    /// `SQLITE_TRANSIENT` makes SQLite copy what it is bound, so the Swift string behind it can
    /// go away as soon as the step returns.
    private static let transient: sqlite3_destructor_type = unsafeBitCast(
        -1, to: sqlite3_destructor_type.self
    )

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            Self.log(sql, in: handle)
            return nil
        }
        return statement
    }

    private static func log(_ sql: String, in handle: OpaquePointer?) {
        #if DEBUG
        let text = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no database"
        FileHandle.standardError.write(Data("[store] \(text) while preparing: \(sql)\n".utf8))
        #endif
    }

    private static func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let statement, let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private static func read(_ statement: OpaquePointer, offset: Int32 = 0) -> StoreTrack {
        let artwork: Data?
        if sqlite3_column_type(statement, offset + 12) == SQLITE_BLOB,
           let bytes = sqlite3_column_blob(statement, offset + 12)
        {
            artwork = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, offset + 12)))
        } else {
            artwork = nil
        }
        return StoreTrack(
            uniqueId: text(statement, offset),
            chatId: sqlite3_column_int64(statement, offset + 1),
            messageId: sqlite3_column_int64(statement, offset + 2),
            fileId: Int(sqlite3_column_int(statement, offset + 3)),
            coverFileId: sqlite3_column_type(statement, offset + 4) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int(statement, offset + 4)),
            title: text(statement, offset + 5),
            performer: text(statement, offset + 6),
            fileName: text(statement, offset + 7),
            duration: sqlite3_column_type(statement, offset + 8) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int(statement, offset + 8)),
            size: sqlite3_column_int64(statement, offset + 9),
            date: sqlite3_column_int64(statement, offset + 10),
            localPath: sqlite3_column_type(statement, offset + 11) == SQLITE_NULL
                ? nil : text(statement, offset + 11),
            miniArtwork: artwork
        )
    }
}

/// Runs a statement that needs no rows back. A message here is only ever a schema or a
/// transaction command, so the error text is dropped rather than threaded up through
/// seventeen call sites.
private func sqlRun(_ handle: OpaquePointer?, _ sql: String) {
    guard let handle else { return }
    var message: UnsafeMutablePointer<CChar>?
    if sqlite3_exec(handle, sql, nil, nil, &message) != SQLITE_OK {
        if let message { sqlite3_free(message) }
    }
}
