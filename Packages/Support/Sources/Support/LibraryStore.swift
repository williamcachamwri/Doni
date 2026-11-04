import Foundation
import SQLite3

/// A music channel the app has been pointed at.
public struct StoreChannel: Equatable, Sendable, Identifiable {
    public var id: Int64 { chatId }
    public var chatId: Int64
    public var username: String
    public var title: String
    /// Whether Doni reads this channel. The allow-list: any number of channels can be on it and the
    /// walk reads all of them, so this is a per-channel yes rather than the one channel home shows.
    public var isIndexed: Bool

    public init(chatId: Int64, username: String, title: String, isIndexed: Bool = false) {
        self.chatId = chatId
        self.username = username
        self.title = title
        self.isIndexed = isIndexed
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
    /// The cover's MTProto identity. `coverFileId` is TDLib's row number in whichever database made
    /// it, so it is only good until that database is; this is what a cached picture is filed under.
    public var coverUniqueId: String?

    public init(uniqueId: String, chatId: Int64, messageId: Int64, fileId: Int,
                coverFileId: Int? = nil, title: String, performer: String, fileName: String,
                duration: Int?, size: Int64, date: Int64, localPath: String? = nil,
                miniArtwork: Data? = nil, coverUniqueId: String? = nil) {
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
        self.coverUniqueId = coverUniqueId
    }
}

/// A list the user made.
public struct StoredPlaylist: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var name: String
    public var createdAt: Int64
    public var trackCount: Int
    /// A picture the user chose for this list, written next to the database. `nil` means the list
    /// wears its first song's cover, which is the only artwork a Telegram list has by itself.
    public var coverPath: String?

    public init(id: Int64, name: String, createdAt: Int64, trackCount: Int = 0,
                coverPath: String? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.trackCount = trackCount
        self.coverPath = coverPath
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
    private static let schemaVersion = 4

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
            is_indexed INTEGER NOT NULL DEFAULT 0
        )
        """)
        renameSelectedColumn(handle)
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
            mini_artwork BLOB,
            cover_unique_id TEXT
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
            created_at INTEGER NOT NULL,
            cover_path TEXT
        )
        """)
        addMissingColumn(handle)
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

    /// A column added later. `CREATE TABLE IF NOT EXISTS` cannot add a column to the table an older
    /// build already made, so the upgrade asks the table what it holds and adds the one it is missing.
    /// Asking rather than reading `user_version` is what keeps this safe on a brand new database,
    /// where the statement above has already made the column and a second one would be an error.
    ///
    /// Version 2 gave a list its own cover file, and version 4 gave a song's cover its own identity:
    /// the row number a pre-4 build stored belongs to whichever TDLib database made it, and a track
    /// that has been re-read since then gets its real `file_unique_id` written beside it.
    private static func addMissingColumn(_ handle: OpaquePointer) {
        if !hasColumn(handle, table: "playlist", column: "cover_path") {
            sqlRun(handle, "ALTER TABLE playlist ADD COLUMN cover_path TEXT")
        }
        if !hasColumn(handle, table: "track", column: "cover_unique_id") {
            sqlRun(handle, "ALTER TABLE track ADD COLUMN cover_unique_id TEXT")
        }
    }

    /// Version 3 changed what a channel row means. `is_selected` could only ever be true for one row
    /// — the one channel the walk was built around — and the allow-list wants a yes for every channel
    /// it reads, so the column keeps its values and takes the new name: the channel an older build
    /// had selected is the channel this build indexes.
    private static func renameSelectedColumn(_ handle: OpaquePointer) {
        guard !hasColumn(handle, table: "channel", column: "is_indexed"),
              hasColumn(handle, table: "channel", column: "is_selected")
        else { return }
        sqlRun(handle, "ALTER TABLE channel RENAME COLUMN is_selected TO is_indexed")
    }

    /// The names a table really has, which is the one thing `CREATE TABLE IF NOT EXISTS` cannot
    /// report about a table an older build already made.
    private static func hasColumn(_ handle: OpaquePointer, table: String,
                                  column: String) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA table_info(\(table))", -1, &statement, nil)
                == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_text(statement, 1) {
            if String(cString: pointer) == column { return true }
        }
        return false
    }

    // MARK: Channels

    public func channels() -> [StoreChannel] {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT chat_id, username, title, is_indexed FROM channel"
            + " ORDER BY title COLLATE NOCASE"
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [StoreChannel] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(StoreChannel(
                chatId: sqlite3_column_int64(statement, 0),
                username: Self.text(statement, 1),
                title: Self.text(statement, 2),
                isIndexed: sqlite3_column_int(statement, 3) != 0
            ))
        }
        return rows
    }

    /// Remembers a channel. Reading it is the app's business, not the row's, so an upsert leaves the
    /// opt-in exactly as the allow-list put it.
    @discardableResult
    public func save(channel: StoreChannel) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            INSERT INTO channel (chat_id, username, title, is_indexed) VALUES (?, ?, ?, ?)
            ON CONFLICT (chat_id) DO UPDATE
            SET username = excluded.username, title = excluded.title
            """) else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, channel.chatId)
        sqlite3_bind_text(statement, 2, channel.username, -1, Self.transient)
        sqlite3_bind_text(statement, 3, channel.title, -1, Self.transient)
        sqlite3_bind_int(statement, 4, channel.isIndexed ? 1 : 0)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// Opting a channel into the index, or back out of it. Every row answers for itself: switching
    /// one on leaves the others on, which is the whole point of an allow-list.
    public func setChannel(chatId: Int64, indexed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("UPDATE channel SET is_indexed = ? WHERE chat_id = ?")
        else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, indexed ? 1 : 0)
        sqlite3_bind_int64(statement, 2, chatId)
        sqlite3_step(statement)
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

    /// A length the app measured and Telegram never sent.
    ///
    /// The walk does not get to disagree: it writes `NULL` for every document row it re-reads and the
    /// upsert's `COALESCE` keeps this instead.
    public func setDuration(_ seconds: Int, uniqueId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("UPDATE track SET duration = ? WHERE unique_id = ?")
        else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(seconds))
        sqlite3_bind_text(statement, 2, uniqueId, -1, Self.transient)
        sqlite3_step(statement)
    }

    /// Songs the list cannot time but the phone could: no duration, and a file to read one from.
    ///
    /// Newest first, the way the list itself is ordered, so what the user is shown is what gets its
    /// timestamp first.
    public func unmeasuredTracks(onlyOnDevice: Bool = true) -> [StoreTrack] {
        lock.lock()
        defer { lock.unlock() }
        let sql = onlyOnDevice
            ? """
            SELECT \(Self.columns) FROM track
            WHERE duration IS NULL AND local_path IS NOT NULL
            ORDER BY date DESC, message_id DESC
            """
            : "SELECT \(Self.columns) FROM track WHERE duration IS NULL ORDER BY date DESC"
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [StoreTrack] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(Self.read(statement)) }
        return rows
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
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                mini_artwork = COALESCE(excluded.mini_artwork, track.mini_artwork),
                cover_unique_id = COALESCE(excluded.cover_unique_id, track.cover_unique_id)
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
        if let coverId = track.coverUniqueId {
            sqlite3_bind_text(statement, 14, coverId, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, 14)
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
                   (SELECT COUNT(*) FROM playlist_track pt WHERE pt.playlist_id = p.id),
                   p.cover_path
            FROM playlist p ORDER BY p.created_at
            """) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [StoredPlaylist] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(StoredPlaylist(
                id: sqlite3_column_int64(statement, 0),
                name: Self.text(statement, 1),
                createdAt: sqlite3_column_int64(statement, 2),
                trackCount: Int(sqlite3_column_int(statement, 3)),
                coverPath: sqlite3_column_type(statement, 4) == SQLITE_NULL
                    ? nil : Self.text(statement, 4)
            ))
        }
        return rows
    }

    /// The picture a list wears. `nil` clears it, which puts the list back on its first song's cover.
    public func setPlaylistCover(id: Int64, path: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("UPDATE playlist SET cover_path = ? WHERE id = ?") else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        switch path {
        case let path?:
            sqlite3_bind_text(statement, 1, path, -1, Self.transient)
        case nil:
            sqlite3_bind_null(statement, 1)
        }
        sqlite3_bind_int64(statement, 2, id)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// The file a list owns, so the one that replaces it can be thrown away with it.
    public func playlistCoverPath(id: Int64) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("SELECT cover_path FROM playlist WHERE id = ?") else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return Self.text(statement, 0)
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

    /// Bytes of audio the phone is holding. `size` is TDLib's `document.size`, written down per
    /// track, so this is the file the app asked for rather than the file's current state on disk —
    /// a row TDLib has since evicted has already had its `local_path` cleared by `verified`.
    public func downloadedBytes() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("SELECT COALESCE(SUM(size), 0) FROM track WHERE local_path IS NOT NULL")
        else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : 0
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
    duration, size, date, local_path, mini_artwork, cover_unique_id
    """

    private static let aliasedColumns = """
    t.unique_id, t.chat_id, t.message_id, t.file_id, t.cover_file_id, t.title, t.performer, \
    t.file_name, t.duration, t.size, t.date, t.local_path, t.mini_artwork, t.cover_unique_id
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
            localPath: optionalText(statement, offset + 11),
            miniArtwork: artwork,
            coverUniqueId: optionalText(statement, offset + 13)
        )
    }

    /// A TEXT column that is allowed to be empty. `text(_:_)` answers `""` for a NULL, which is the
    /// wrong thing for an identity: an empty cover id would be read as a real one and file a picture
    /// under nothing.
    private static func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = text(statement, index)
        return value.isEmpty ? nil : value
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
