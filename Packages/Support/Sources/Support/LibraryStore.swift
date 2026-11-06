import Foundation
import SQLite3

/// A music channel the app has been pointed at.
public struct StoreChannel: Equatable, Sendable, Identifiable {
    public var id: Int64 { chatId }
    public var chatId: Int64
    public var username: String
    public var title: String
    /// Whether Doni indexes this channel. The allow-list can hold any number of them.
    public var isIndexed: Bool
    /// TDLib's row number for the chat's picture (`td_api.tl:326`) — what a download is asked for
    /// by. `nil` until `getChat` has been read.
    public var avatarFileId: Int?
    /// MTProto's identity for the same bytes (`td_api.tl:784`), which the local copy is named after.
    /// A row number is per-database, so it cannot key a picture that outlives its database.
    public var avatarUniqueId: String?
    /// This app's own copy, so the row draws the picture without asking Telegram again.
    public var avatarPath: String?

    public init(chatId: Int64, username: String, title: String, isIndexed: Bool = false,
                avatarFileId: Int? = nil, avatarUniqueId: String? = nil,
                avatarPath: String? = nil) {
        self.chatId = chatId
        self.username = username
        self.title = title
        self.isIndexed = isIndexed
        self.avatarFileId = avatarFileId
        self.avatarUniqueId = avatarUniqueId
        self.avatarPath = avatarPath
    }
}

/// A playable message, written down.
///
/// A snapshot, not a live `TdTrack`: favourites and playlist entries have to survive a re-read, and
/// `file:id:int32` (`td_api.tl:326`) is per-database — MTProto's `unique_id` is the only stable key.
public struct StoreTrack: Equatable, Sendable, Identifiable {
    public var id: String { uniqueId }
    public var uniqueId: String
    /// The channel that posted it, or `0` for a file the user brought in — the gap Telegram does not
    /// number, which is what `isLocal` asks.
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
    /// The cover's MTProto identity — what a cached picture is filed under, because `coverFileId` is
    /// only good while the database that made it is.
    public var coverUniqueId: String?
    /// What Telegram said the bytes are. Channel posts so often carry no file name that this is the
    /// only thing to read the container from; lost, the row is called unstreamable and downloaded whole.
    public var mimeType: String

    public init(uniqueId: String, chatId: Int64, messageId: Int64, fileId: Int,
                coverFileId: Int? = nil, title: String, performer: String, fileName: String,
                duration: Int?, size: Int64, date: Int64, localPath: String? = nil,
                miniArtwork: Data? = nil, coverUniqueId: String? = nil, mimeType: String = "") {
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
        self.mimeType = mimeType
    }

    /// A file the user imported, not a channel post: `fileId` is `0` because TDLib never saw the
    /// file, the cover comes out of the container, and the bytes stay until the user deletes them.
    /// Every walk writes under a real `chat_id`, so a re-read never prunes these.
    public var isLocal: Bool { chatId == 0 }
}

/// A list the user made.
public struct StoredPlaylist: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var name: String
    public var createdAt: Int64
    public var trackCount: Int
    /// A cover the user chose, written next to the database; `nil` wears the first song's cover.
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
    /// The slice kept, in seconds; `nil` means the whole song.
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

/// The app's own database, in SQLite: hand-rolled, because five tables and a 50 000-row library
/// answering "which of these are on the phone" should not carry an ORM. One class, one lock.
public final class LibraryStore: @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case cannotOpen(String)
        case statement(String)
    }

    /// `1` is the first schema; a column added later bumps this and the row below it migrates.
    private static let schemaVersion = 7

    private let lock = NSLock()
    private var handle: OpaquePointer?
    private let path: String

    /// The last thing the database refused to do, in the app's own words. Without this a store that
    /// never opened — every read `[]`, every write a no-op — is indistinguishable from an empty
    /// library. What arrives here is an open that failed and a statement SQLite would not prepare;
    /// a write refused at step time (disk full) is still dropped quietly rather than reported.
    public private(set) var failure: String?

    /// Opens (and creates if needed) the database at `path`.
    public init(path: String) {
        self.path = path
        open()
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

    /// Closes and reopens the same path, so a sign-out can unlink the *file* rather than only its
    /// rows: the unlink needs no open handle. Comes back as the empty schema a first launch gets.
    public func reopen() {
        lock.lock()
        defer { lock.unlock() }
        if let handle { sqlite3_close_v2(handle) }
        handle = nil
        open()
    }

    /// The caller holds the lock.
    private func open() {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let opened else {
            handle = nil
            let text = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle"
            failure = "Không mở được thư viện nhạc: \(text)"
            return
        }
        handle = opened
        sqlite3_busy_timeout(opened, 2000)
        // Whatever the schema work reports is the store's to carry, not the free function's.
        _ = drainSchemaProblems()
        Self.configure(opened)
        Self.createSchema(opened)
        // A schema that could not be built saves nothing, even though the file opened fine.
        if let problem = drainSchemaProblems().first {
            failure = "Không dựng được cấu trúc thư viện: \(problem)"
        }
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
            is_indexed INTEGER NOT NULL DEFAULT 0,
            avatar_file_id INTEGER,
            avatar_unique_id TEXT,
            avatar_path TEXT
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
            cover_unique_id TEXT,
            mime_type TEXT NOT NULL DEFAULT '',
            in_cloud INTEGER NOT NULL DEFAULT 0
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

    /// A column added later: `CREATE TABLE IF NOT EXISTS` cannot extend a table an older build already
    /// made, so each upgrade asks the table what it holds (`hasColumn`) and adds only what is missing —
    /// probing rather than reading `PRAGMA user_version` is what keeps a brand new database safe, where
    /// the create above already made these columns and a second one would error.
    ///
    /// Versions 2-5: a list's own cover, then the `file_unique_id` a cover or avatar is filed under.
    /// Version 6: the mime type a container is read from, and the moment a song was last heard.
    /// Version 7: `in_cloud` — a song can be a channel's post and the account's own file at once, and
    /// one `chat_id` cannot say both.
    private static func addMissingColumn(_ handle: OpaquePointer) {
        if !hasColumn(handle, table: "playlist", column: "cover_path") {
            sqlRun(handle, "ALTER TABLE playlist ADD COLUMN cover_path TEXT")
        }
        if !hasColumn(handle, table: "track", column: "cover_unique_id") {
            sqlRun(handle, "ALTER TABLE track ADD COLUMN cover_unique_id TEXT")
        }
        if !hasColumn(handle, table: "channel", column: "avatar_file_id") {
            sqlRun(handle, "ALTER TABLE channel ADD COLUMN avatar_file_id INTEGER")
        }
        if !hasColumn(handle, table: "channel", column: "avatar_unique_id") {
            sqlRun(handle, "ALTER TABLE channel ADD COLUMN avatar_unique_id TEXT")
        }
        if !hasColumn(handle, table: "channel", column: "avatar_path") {
            sqlRun(handle, "ALTER TABLE channel ADD COLUMN avatar_path TEXT")
        }
        if !hasColumn(handle, table: "track", column: "mime_type") {
            // What the post said the bytes are: the file name is so often absent that guessing the
            // container wrong costs the song its streaming.
            sqlRun(handle, "ALTER TABLE track ADD COLUMN mime_type TEXT NOT NULL DEFAULT ''")
        }
        if !hasColumn(handle, table: "track", column: "last_played_at") {
            // When a song was last heard — the only fact a cache can be pruned by. A post's own date
            // says only when it was published.
            sqlRun(handle, "ALTER TABLE track ADD COLUMN last_played_at INTEGER")
        }
        if !hasColumn(handle, table: "track", column: "in_cloud") {
            // Whether the account's own chat holds this song, as its own fact: `chat_id` is the
            // channel that posted it, so overwriting it takes the song out of that channel's list.
            sqlRun(handle, "ALTER TABLE track ADD COLUMN in_cloud INTEGER NOT NULL DEFAULT 0")
        }
    }

    /// Version 3: `is_selected` could only be true for one row and the allow-list wants a yes per
    /// channel, so the column keeps its values and takes the new name.
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
        let sql = """
        SELECT chat_id, username, title, is_indexed, avatar_file_id, avatar_unique_id, avatar_path
        FROM channel ORDER BY title COLLATE NOCASE
        """
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [StoreChannel] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(StoreChannel(
                chatId: sqlite3_column_int64(statement, 0),
                username: Self.text(statement, 1),
                title: Self.text(statement, 2),
                isIndexed: sqlite3_column_int(statement, 3) != 0,
                avatarFileId: Self.optionalInt(statement, 4),
                avatarUniqueId: Self.optionalText(statement, 5),
                avatarPath: Self.optionalText(statement, 6)
            ))
        }
        return rows
    }

    /// Remembers a channel, leaving the opt-in exactly as the allow-list put it and any picture
    /// already recorded — the adding screen knows a cover, not yet whether the bytes landed.
    @discardableResult
    public func save(channel: StoreChannel) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            INSERT INTO channel (chat_id, username, title, is_indexed,
                                 avatar_file_id, avatar_unique_id, avatar_path)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (chat_id) DO UPDATE
            SET username = excluded.username, title = excluded.title,
                avatar_file_id = COALESCE(excluded.avatar_file_id, channel.avatar_file_id),
                avatar_unique_id = COALESCE(excluded.avatar_unique_id, channel.avatar_unique_id),
                avatar_path = COALESCE(excluded.avatar_path, channel.avatar_path)
            """) else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, channel.chatId)
        sqlite3_bind_text(statement, 2, channel.username, -1, Self.transient)
        sqlite3_bind_text(statement, 3, channel.title, -1, Self.transient)
        sqlite3_bind_int(statement, 4, channel.isIndexed ? 1 : 0)
        Self.bindOptional(statement, 5, channel.avatarFileId.map(Int64.init))
        Self.bindOptional(statement, 6, channel.avatarUniqueId)
        Self.bindOptional(statement, 7, channel.avatarPath)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// Records a channel's picture as each half is learned. A `nil` leaves its column alone rather
    /// than clearing it, so recording cannot undo a copy already kept.
    @discardableResult
    public func setChannelAvatar(chatId: Int64, fileId: Int?, uniqueId: String?,
                                 path: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            UPDATE channel
            SET avatar_file_id = COALESCE(?, avatar_file_id),
                avatar_unique_id = COALESCE(?, avatar_unique_id),
                avatar_path = COALESCE(?, avatar_path)
            WHERE chat_id = ?
            """) else { return false }
        defer { sqlite3_finalize(statement) }
        Self.bindOptional(statement, 1, fileId.map(Int64.init))
        Self.bindOptional(statement, 2, uniqueId)
        Self.bindOptional(statement, 3, path)
        sqlite3_bind_int64(statement, 4, chatId)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// Opting a channel into the index, or back out. Every row answers for itself, as an allow-list wants.
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
        // The songs go with it, and anything that pointed at them: an unreachable row never plays.
        sqlRun(handle, "BEGIN")
        let owned = "(SELECT unique_id FROM track WHERE chat_id = \(chatId))"
        sqlRun(handle, "DELETE FROM favorite WHERE unique_id IN \(owned)")
        sqlRun(handle, "DELETE FROM playlist_track WHERE unique_id IN \(owned)")
        sqlRun(handle, "DELETE FROM track WHERE chat_id = \(chatId)")
        sqlRun(handle, "DELETE FROM channel WHERE chat_id = \(chatId)")
        sqlRun(handle, "COMMIT")
    }

    // MARK: Tracks

    /// Writes a page of the library. The write is an upsert, so a re-stated song keeps the path
    /// already recorded; a song the page no longer mentions is retired with its channel.
    public func replaceTracks(chatId: Int64, tracks: [StoreTrack]) {
        lock.lock()
        defer { lock.unlock() }
        sqlRun(handle, "BEGIN")
        // Written under the channel being replaced, so a page carrying the wrong `chat_id` cannot
        // leave a song behind that no channel can reach.
        for track in tracks {
            var owned = track
            owned.chatId = chatId
            insert(track: owned)
        }
        pruneTracks(chatId: chatId, keeping: tracks.map { $0.uniqueId })
        sqlRun(handle, "COMMIT")
    }

    /// A walk writes pages newest first, so they overlap; the upsert underneath lets an overlap
    /// update a row without forgetting where its file is.
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

    /// The songs the user brought in themselves — the rows no channel answers for.
    public func localTracks() -> [StoreTrack] {
        tracks(chatId: 0)
    }

    /// Retiring a song and everything that pointed at it, as `removeChannel` does per channel. The id
    /// is bound, not spliced: neither Telegram's bytes nor an import hash belongs in the SQL text.
    public func removeTrack(uniqueId: String) {
        lock.lock()
        defer { lock.unlock() }
        sqlRun(handle, "BEGIN")
        for table in ["favorite", "playlist_track", "track"] {
            guard let statement = prepare("DELETE FROM \(table) WHERE unique_id = ?") else { break }
            sqlite3_bind_text(statement, 1, uniqueId, -1, Self.transient)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        sqlRun(handle, "COMMIT")
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

    /// A length the app measured and Telegram never sent. The walk writes `NULL` for every document
    /// row it re-reads and the upsert's `COALESCE` keeps this instead.
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

    /// Songs with no duration but a file on the phone to read one from, newest first as the list is.
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
        // Index 1 is the channel, so the list starts at 2 — bound onto 1 would leave a NULL in the
        // last slot, which makes `NOT IN` match nothing at all.
        for (offset, key) in uniqueIds.enumerated() {
            sqlite3_bind_text(statement, Int32(2 + offset), key, -1, Self.transient)
        }
        sqlite3_step(statement)
    }

    private func insert(track: StoreTrack) {
        guard let statement = prepare("""
            INSERT INTO track (\(Self.columns))
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(unique_id) DO UPDATE SET
                chat_id = excluded.chat_id,
                // A song that is also in Saved Messages keeps that post's id, because that id is the only
                // handle a delete update gives the cloud list. `saveCloud` is the writer allowed to move
                // it; a channel walk that posted the same song elsewhere must not.
                message_id = CASE WHEN track.in_cloud = 1 THEN track.message_id
                                  ELSE excluded.message_id END,
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
                cover_unique_id = COALESCE(excluded.cover_unique_id, track.cover_unique_id),
                mime_type = excluded.mime_type
            """) else { return }
        defer { sqlite3_finalize(statement) }
        Self.bind(track: track, into: statement)
        sqlite3_step(statement)
    }

    /// The fifteen columns, in `Self.columns` order, bound onto a statement — shared by the walk's
    /// upsert and the cloud's, which write the same row and disagree only about what they may
    /// overwrite; a column list kept in two places gets out of order.
    private static func bind(track: StoreTrack, into statement: OpaquePointer) {
        sqlite3_bind_text(statement, 1, track.uniqueId, -1, transient)
        sqlite3_bind_int64(statement, 2, track.chatId)
        sqlite3_bind_int64(statement, 3, track.messageId)
        sqlite3_bind_int(statement, 4, Int32(track.fileId))
        bindOptional(statement, 5, track.coverFileId.map(Int64.init))
        sqlite3_bind_text(statement, 6, track.title, -1, transient)
        sqlite3_bind_text(statement, 7, track.performer, -1, transient)
        sqlite3_bind_text(statement, 8, track.fileName, -1, transient)
        bindOptional(statement, 9, track.duration.map(Int64.init))
        sqlite3_bind_int64(statement, 10, track.size)
        sqlite3_bind_int64(statement, 11, track.date)
        bindOptional(statement, 12, track.localPath)
        if let artwork = track.miniArtwork {
            _ = artwork.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, 13, buffer.baseAddress, Int32(buffer.count), transient)
            }
        } else {
            sqlite3_bind_null(statement, 13)
        }
        bindOptional(statement, 14, track.coverUniqueId)
        sqlite3_bind_text(statement, 15, track.mimeType, -1, transient)
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

    /// Writing a slice onto a favourite that already exists.
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

    /// Every row claiming a file on the phone, as name and path only: a sweep about paths has no
    /// use for a library's worth of `mini_artwork` blobs.
    public func localPaths() -> [(uniqueId: String, path: String)] {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare(
            "SELECT unique_id, local_path FROM track WHERE local_path IS NOT NULL"
        ) else { return [] }
        defer { sqlite3_finalize(statement) }
        var found: [(String, String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            found.append((Self.text(statement, 0), Self.text(statement, 1)))
        }
        return found
    }

    /// The moment a song was heard, and the row it was heard from. Written as well as updated: TDLib
    /// hands over bytes of a Saved Messages post the walk has not listed yet, and an `UPDATE` over no
    /// row loses it. Only the listener's columns are touched — `mime_type`, `duration` and
    /// `local_path` stay as the walk put them.
    public func markPlayed(_ row: StoreTrack, at seconds: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            INSERT INTO track (unique_id, chat_id, message_id, file_id, title, performer,
                               file_name, size, date, last_played_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(unique_id) DO UPDATE SET last_played_at = excluded.last_played_at
            """) else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, row.uniqueId, -1, Self.transient)
        sqlite3_bind_int64(statement, 2, row.chatId)
        sqlite3_bind_int64(statement, 3, row.messageId)
        sqlite3_bind_int(statement, 4, Int32(row.fileId))
        sqlite3_bind_text(statement, 5, row.title, -1, Self.transient)
        sqlite3_bind_text(statement, 6, row.performer, -1, Self.transient)
        sqlite3_bind_text(statement, 7, row.fileName, -1, Self.transient)
        sqlite3_bind_int64(statement, 8, row.size)
        sqlite3_bind_int64(statement, 9, row.date)
        sqlite3_bind_int64(statement, 10, seconds)
        sqlite3_step(statement)
    }

    /// The songs the phone has heard, most recent first; `limit` because this feeds a shelf of cards.
    public func recentlyPlayed(limit: Int) -> [StoreTrack] {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            SELECT \(Self.columns) FROM track
            WHERE last_played_at IS NOT NULL
            ORDER BY last_played_at DESC LIMIT ?
            """) else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var rows: [StoreTrack] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(Self.read(statement)) }
        return rows
    }

    // MARK: The account's own chat

    /// Writing the songs of Saved Messages into the library, marked with `in_cloud`.
    ///
    /// An existing row keeps its `chat_id` — a forward into Saved Messages does not move the post —
    /// and the separate flag is what lets one song stand in its channel's list and in Cloud Music. A
    /// page answering before TDLib finishes the lookup must not make a column worse, so length, cover
    /// and the streaming gate's mime type are `COALESCE`d, not replaced.
    public func saveCloud(_ tracks: [StoreTrack]) {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            INSERT INTO track (\(Self.columns), in_cloud)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            ON CONFLICT(unique_id) DO UPDATE SET
                in_cloud = 1,
                file_id = excluded.file_id,
                // The Saved Messages post id, not the channel's: a delete update names the chat it was
                // read from, and this row's only handle on that chat is the id written here. A song
                // imported from Files carries 0 until the cloud walk gives it one.
                message_id = excluded.message_id,
                title = CASE WHEN track.title = '' THEN excluded.title ELSE track.title END,
                duration = COALESCE(excluded.duration, track.duration),
                local_path = COALESCE(excluded.local_path, track.local_path),
                mini_artwork = COALESCE(excluded.mini_artwork, track.mini_artwork),
                cover_file_id = COALESCE(excluded.cover_file_id, track.cover_file_id),
                cover_unique_id = COALESCE(excluded.cover_unique_id, track.cover_unique_id),
                mime_type = CASE WHEN track.mime_type = '' THEN excluded.mime_type
                                 ELSE track.mime_type END
            """) else { return }
        defer { sqlite3_finalize(statement) }
        sqlRun(handle, "BEGIN")
        for track in tracks { Self.bind(track: track, into: statement); sqlite3_step(statement) }
        sqlRun(handle, "COMMIT")
    }

    /// The songs the account's own chat holds, newest post first.
    public func cloudTracks() -> [StoreTrack] {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
            SELECT \(Self.columns) FROM track WHERE in_cloud = 1
            ORDER BY date DESC, message_id DESC
            """) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [StoreTrack] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(Self.read(statement)) }
        return rows
    }

    /// Whether the cloud already holds this exact song — the question a second Download asks.
    public func isInCloud(uniqueId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("SELECT 1 FROM track WHERE unique_id = ? AND in_cloud = 1")
        else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uniqueId, -1, Self.transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// Taking the flag off songs the chat no longer holds, within the part of the chat a read saw to its
    /// bottom. `newerThan` is the oldest message id the walk reached: every row above it is either in
    /// `keep` or gone, and every row at or below it is something this read never looked at, so it keeps
    /// its flag. Pass 0 for a read that reached the oldest message in the chat.
    public func clearCloud(newerThan: Int64, except uniqueIds: [String]) {
        lock.lock()
        defer { lock.unlock() }
        let keep = Set(uniqueIds)
        clearCloudFlagsLocked(cloudRowsLocked().filter { $0.id > newerThan && !keep.contains($0.key) }
                                                     .map(\.key))
    }

    /// Taking the flag off the songs posted under the message ids Telegram says are gone.
    ///
    /// This is what a delete update can answer with on its own. A Saved Messages chat of a few thousand
    /// posts is never walked to its end inside one app session, so a rule that waits for a full read
    /// before it dares to clear anything is a rule that never clears anything — which is how a song
    /// deleted in Telegram stayed on this list.
    public func clearCloud(messageIds: [Int64]) {
        guard !messageIds.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var index = 0
        while index < messageIds.count {
            let chunk = Array(messageIds[index..<min(index + 500, messageIds.count)])
            index += chunk.count
            let marks = repeatElement("?", count: chunk.count).joined(separator: ", ")
            guard let statement = prepare(
                "UPDATE track SET in_cloud = 0 WHERE message_id IN (\(marks))"
            ) else { return }
            for (offset, id) in chunk.enumerated() {
                sqlite3_bind_int64(statement, Int32(1 + offset), id)
            }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    /// The old rule, for the one caller that really does know the whole chat.
    public func clearCloud(except uniqueIds: [String]) {
        lock.lock()
        defer { lock.unlock() }
        let keep = Set(uniqueIds)
        clearCloudFlagsLocked(cloudRowsLocked().filter { !keep.contains($0.key) }.map(\.key))
    }

    private func clearCloudFlagsLocked(_ gone: [String]) {
        guard !gone.isEmpty else { return }
        var index = 0
        while index < gone.count {
            let chunk = Array(gone[index..<min(index + 500, gone.count)])
            index += chunk.count
            let marks = repeatElement("?", count: chunk.count).joined(separator: ", ")
            guard let statement = prepare(
                "UPDATE track SET in_cloud = 0 WHERE unique_id IN (\(marks))"
            ) else { return }
            for (offset, key) in chunk.enumerated() {
                sqlite3_bind_text(statement, Int32(1 + offset), key, -1, Self.transient)
            }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    /// The cloud's rows with the message id each was posted under, which is the only number a delete
    /// update speaks.
    private func cloudRowsLocked() -> [(key: String, id: Int64)] {
        guard let statement = prepare("SELECT unique_id, message_id FROM track WHERE in_cloud = 1")
        else { return [] }
        defer { sqlite3_finalize(statement) }
        var found: [(String, Int64)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            found.append((Self.text(statement, 0), sqlite3_column_int64(statement, 1)))
        }
        return found
    }

    /// Writing or clearing the cloud flag on named songs.
    ///
    /// Used by the swipe, which knows exactly which song Telegram just lost and should not wait for a
    /// page read to agree. Chunked at 500 because SQLite's variable limit is a real number.
    public func setCloud(_ on: Bool, uniqueIds: [String]) {
        guard !uniqueIds.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var index = 0
        while index < uniqueIds.count {
            let chunk = Array(uniqueIds[index..<min(index + 500, uniqueIds.count)])
            index += chunk.count
            let marks = repeatElement("?", count: chunk.count).joined(separator: ", ")
            guard let statement = prepare(
                "UPDATE track SET in_cloud = ? WHERE unique_id IN (\(marks))"
            ) else { return }
            sqlite3_bind_int(statement, 1, on ? 1 : 0)
            for (offset, key) in chunk.enumerated() {
                sqlite3_bind_text(statement, Int32(2 + offset), key, -1, Self.transient)
            }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    /// What the phone holds per song, in the numbers an eviction decides with. `size` is what the post
    /// said the file was, not what the directory measures — a per-row `stat` over thousands of files
    /// is the slow way to ask what the storage screen already answered once a launch.
    public func cacheRows() -> [(uniqueId: String, fileId: Int, size: Int64,
                                isComplete: Bool, lastPlayedAt: Int64?)] {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare(
            "SELECT unique_id, file_id, size, local_path, last_played_at FROM track"
        ) else { return [] }
        defer { sqlite3_finalize(statement) }
        var found: [(String, Int, Int64, Bool, Int64?)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let path = sqlite3_column_text(statement, 3)
            let complete = path != nil && !Self.text(statement, 3).isEmpty
            let played = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil : sqlite3_column_int64(statement, 4)
            found.append((Self.text(statement, 0), Int(sqlite3_column_int(statement, 1)),
                          sqlite3_column_int64(statement, 2), complete, played))
        }
        return found
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

    /// Bytes of audio the phone is holding: TDLib's `document.size` per row, so the file the app asked
    /// for rather than its state on disk. A row TDLib has evicted has already had `local_path` cleared
    /// by `verified`.
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
    duration, size, date, local_path, mini_artwork, cover_unique_id, mime_type
    """

    private static let aliasedColumns = """
    t.unique_id, t.chat_id, t.message_id, t.file_id, t.cover_file_id, t.title, t.performer, \
    t.file_name, t.duration, t.size, t.date, t.local_path, t.mini_artwork, t.cover_unique_id, \
    t.mime_type
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
            // Worth reporting: the handle here is an open one, and a closed one failed above.
            failure = "Thư viện nhạc không đọc được câu truy vấn này: \(sql)"
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
            coverUniqueId: optionalText(statement, offset + 13),
            mimeType: text(statement, offset + 14)
        )
    }

    /// A TEXT column that is allowed to be empty. `text(_:_)` answers `""` for a NULL, which would
    /// read as a real identity and file a picture under nothing.
    private static func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = text(statement, index)
        return value.isEmpty ? nil : value
    }

    /// An INTEGER column allowed to be absent — a picture not read yet is not a picture that is zero.
    private static func optionalInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    /// Binding an absent value as `NULL`, which is what the `COALESCE` above reads as "leave the
    /// column alone" — never as a zero or an empty string.
    private static func bindOptional(_ statement: OpaquePointer?, _ index: Int32,
                                     _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private static func bindOptional(_ statement: OpaquePointer?, _ index: Int32,
                                     _ value: Int64?) {
        if let value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}

/// Schema and transaction statements run through a free function, so a failure goes into a
/// process-wide box the store drains when it finishes opening; the lock is because tests share it.
private let schemaProblemsLock = NSLock()
// Every read and write goes through the lock above, which is what makes the Swift 6 opt-out honest.
private nonisolated(unsafe) var schemaProblems: [String] = []

private func drainSchemaProblems() -> [String] {
    schemaProblemsLock.withLock {
        let found = schemaProblems
        schemaProblems = []
        return found
    }
}

private func sqlRun(_ handle: OpaquePointer?, _ sql: String) {
    guard let handle else { return }
    var message: UnsafeMutablePointer<CChar>?
    if sqlite3_exec(handle, sql, nil, nil, &message) != SQLITE_OK {
        let text = message.map { String(cString: $0) } ?? sql
        if let message { sqlite3_free(message) }
        schemaProblemsLock.withLock { schemaProblems.append(text) }
    }
}
