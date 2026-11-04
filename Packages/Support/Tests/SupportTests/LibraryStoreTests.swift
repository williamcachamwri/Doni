import Foundation
import SQLite3
import Testing
@testable import Support

/// A database in a temporary directory, thrown away when the test ends.
private func makeStore() throws -> (LibraryStore, URL) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("doni-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (LibraryStore(path: directory.appendingPathComponent("library.db").path), directory)
}

/// Runs a statement against a hand-built database, for the tests that need the schema an older
/// build made rather than the one this build asks for.
private func sql(_ handle: OpaquePointer?, _ statement: String) {
    sqlite3_exec(handle, statement, nil, nil, nil)
}

private func track(_ key: String, chatId: Int64 = -1001, date: Int64 = 1_730_000_000,
                   title: String = "Bài hát") -> StoreTrack {
    let number = Int64(key.unicodeScalars.first?.value ?? 0)
    return StoreTrack(uniqueId: key, chatId: chatId, messageId: number,
                      fileId: 10, coverFileId: 20, title: title, performer: "Sơn Tùng M-TP",
                      fileName: "\(key).mp3", duration: 200, size: 5_000_000, date: date)
}

@Suite("LibraryStore")
struct LibraryStoreTests {
    @Test("an empty database answers with empty lists, not an error")
    func freshDatabaseIsEmpty() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        #expect(store.channels().isEmpty)
        #expect(store.tracks().isEmpty)
        #expect(store.favorites().isEmpty)
        #expect(store.playlists().isEmpty)
        #expect(store.trackCount() == 0)
        #expect(store.downloadedBytes() == 0)
    }

    @Test("a second open of the same file finds what the first wrote")
    func rowsSurviveReopen() throws {
        let (store, directory) = try makeStore()
        let path = directory.appendingPathComponent("library.db").path
        store.save(channel: StoreChannel(chatId: -1002, username: "vn", title: "VN Music"))
        store.replaceTracks(chatId: -1002, tracks: [track("u1"), track("u2")])
        store.close()

        let reopened = LibraryStore(path: path)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(reopened.trackCount(chatId: -1002) == 2)
        #expect(reopened.channels().map { $0.title } == ["VN Music"])
        reopened.close()
    }

    @Test("every channel on the allow-list is indexed, not only the last one switched on")
    func indexingIsPerChannel() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.save(channel: StoreChannel(chatId: -1, username: "a", title: "A"))
        store.save(channel: StoreChannel(chatId: -2, username: "b", title: "B"))
        store.setChannel(chatId: -1, indexed: true)
        store.setChannel(chatId: -2, indexed: true)
        #expect(store.channels().filter(\.isIndexed).map { $0.chatId } == [-1, -2])
        store.setChannel(chatId: -1, indexed: false)
        #expect(store.channels().filter(\.isIndexed).map { $0.chatId } == [-2])
    }

    @Test("a channel the walk re-reads stays on, or off, the way the list put it")
    func upsertKeepsTheOptIn() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.save(channel: StoreChannel(chatId: -1, username: "a", title: "A", isIndexed: true))
        store.save(channel: StoreChannel(chatId: -1, username: "a", title: "Renamed"))
        #expect(store.channels().first?.isIndexed == true)
        #expect(store.channels().first?.title == "Renamed")
    }

    @Test("a database from the one-channel build keeps its selected channel indexed")
    func selectedColumnMigratesToIndexed() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doni-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("library.db").path
        defer { try? FileManager.default.removeItem(at: directory) }

        // Schema 2, written by hand: a channel table whose single flag could only ever be true for
        // one row. Opening it has to carry that row's value into the flag the allow-list reads.
        var old: OpaquePointer?
        #expect(sqlite3_open(path, &old) == SQLITE_OK)
        sql(old, "CREATE TABLE channel (chat_id INTEGER PRIMARY KEY, username TEXT NOT NULL,"
            + " title TEXT NOT NULL, is_selected INTEGER NOT NULL DEFAULT 0)")
        sql(old, "INSERT INTO channel VALUES (-1002, 'vn', 'VN Music', 1)")
        sqlite3_close(old)

        let store = LibraryStore(path: path)
        defer { store.close() }
        #expect(store.channels() == [StoreChannel(chatId: -1002, username: "vn",
                                                  title: "VN Music", isIndexed: true)])
    }

    @Test("saving a channel twice updates it instead of doubling it")
    func channelUpsert() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.save(channel: StoreChannel(chatId: -1, username: "a", title: "Old"))
        store.save(channel: StoreChannel(chatId: -1, username: "a", title: "New"))
        #expect(store.channels().count == 1)
        #expect(store.channels().first?.title == "New")
    }

    @Test("the library reads newest first, the way a chat does")
    func tracksComeBackNewestFirst() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [
            track("old", date: 1_000), track("new", date: 2_000), track("mid", date: 1_500)
        ])
        #expect(store.tracks().map { $0.uniqueId } == ["new", "mid", "old"])
    }

    @Test("the same file id twice in two channels is stored once")
    func dedupesByUniqueId() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("dup")])
        store.appendTracks([track("dup", chatId: -2, title: "Bài khác")])
        #expect(store.trackCount() == 1)
        #expect(store.track(uniqueId: "dup")?.title == "Bài khác")
    }

    @Test("a full page replaces the page before it")
    func replaceClearsTheChannel() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a"), track("b")])
        store.replaceTracks(chatId: -1, tracks: [track("b"), track("c")])
        #expect(store.tracks(chatId: -1).map { $0.uniqueId }.sorted() == ["b", "c"])
    }

    @Test("where the file landed is written back onto the row")
    func localPathIsRemembered() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        #expect(store.downloadedCount() == 0)
        store.setLocalPath("/tmp/a.mp3", uniqueId: "a")
        #expect(store.track(uniqueId: "a")?.localPath == "/tmp/a.mp3")
        #expect(store.downloadedCount() == 1)
        store.setLocalPath(nil, uniqueId: "a")
        #expect(store.track(uniqueId: "a")?.localPath == nil)
    }

    @Test("the offline total counts the files on the phone, not the library")
    func downloadedBytesFollowsLocalPaths() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a"), track("b"), track("c")])
        #expect(store.downloadedBytes() == 0)
        store.setLocalPath("/tmp/a.mp3", uniqueId: "a")
        store.setLocalPath("/tmp/b.mp3", uniqueId: "b")
        #expect(store.downloadedBytes() == 10_000_000)
        store.setLocalPath(nil, uniqueId: "a")
        #expect(store.downloadedBytes() == 5_000_000)
    }

    @Test("a page that repeats a song keeps the file already on the phone")
    func rereadingKeepsTheDownload() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.appendTracks([track("a")])
        store.setLocalPath("/tmp/a.mp3", uniqueId: "a")
        // A walk re-reads the same message and reports no path: the row must stay playable.
        store.appendTracks([track("a")])
        #expect(store.track(uniqueId: "a")?.localPath == "/tmp/a.mp3")
        #expect(store.downloadedCount() == 1)
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        #expect(store.track(uniqueId: "a")?.localPath == "/tmp/a.mp3")
    }

    @Test("a re-read with no thumbnail keeps the one already stored")
    func rereadingKeepsTheArtwork() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        var row = track("a")
        row.miniArtwork = Data([0xff, 0xd8, 0x01])
        store.appendTracks([row])
        store.appendTracks([track("a")])
        #expect(store.track(uniqueId: "a")?.miniArtwork == Data([0xff, 0xd8, 0x01]))
    }

    @Test("an empty page clears its channel")
    func emptyPageClearsTheChannel() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a"), track("b")])
        store.replaceTracks(chatId: -1, tracks: [])
        #expect(store.tracks(chatId: -1).isEmpty)
        #expect(store.trackCount() == 0)
    }

    @Test("the cover's own id and the inline artwork survive the round trip")
    func artworkColumns() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        var row = track("a")
        row.miniArtwork = Data([0xff, 0xd8, 0x01])
        row.coverUniqueId = "AQADFR4AAn3M-VZy"
        store.replaceTracks(chatId: -1, tracks: [row])
        let read = try #require(store.track(uniqueId: "a"))
        #expect(read.coverFileId == 20)
        #expect(read.coverUniqueId == "AQADFR4AAn3M-VZy")
        #expect(read.miniArtwork == Data([0xff, 0xd8, 0x01]))
    }

    @Test("a re-read that names no cover keeps the name already stored")
    func rereadingKeepsTheCoverName() throws {
        // A row written before covers had their own column, or a page TDLib answered without the
        // remote, must not blank the identity the picture is filed under.
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        var row = track("a")
        row.coverUniqueId = "AQADFR4AAn3M-VZy"
        store.replaceTracks(chatId: -1, tracks: [row])
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        #expect(store.track(uniqueId: "a")?.coverUniqueId == "AQADFR4AAn3M-VZy")
    }

    @Test("a heart on, then off, then on again")
    func favoriteToggles() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        #expect(store.toggleFavorite(uniqueId: "a", segment: nil) == true)
        #expect(store.isFavorite("a"))
        #expect(store.favorites().count == 1)
        #expect(store.favorites().first?.segment == nil)
        #expect(store.toggleFavorite(uniqueId: "a", segment: nil) == false)
        #expect(!store.isFavorite("a"))
        #expect(store.favorites().isEmpty)
    }

    @Test("a heart can hold three minutes of a one-hour set")
    func favoriteSegmentRoundTrips() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        #expect(store.toggleFavorite(uniqueId: "a", segment: 72...100))
        #expect(store.favoriteSegment("a") == 72...100)
        #expect(store.favorites().first?.segment == 72...100)
    }

    @Test("a whole favourite can be narrowed to a slice without losing the heart")
    func settingASegmentOnAnExistingFavourite() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        store.toggleFavorite(uniqueId: "a", segment: nil)
        #expect(store.setFavoriteSegment(10...20, uniqueId: "a"))
        #expect(store.isFavorite("a"))
        #expect(store.favoriteSegment("a") == 10...20)
    }

    @Test("a favourite whose song is gone is not a favourite at all")
    func favouritesJoinTheTrack() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a"), track("b")])
        store.toggleFavorite(uniqueId: "a", segment: nil)
        store.replaceTracks(chatId: -1, tracks: [track("b")])
        #expect(store.isFavorite("a"), "the heart is still pressed")
        #expect(store.favorites().isEmpty, "but there is nothing left to play")
    }

    @Test("a playlist name has to be new and not blank")
    func playlistNames() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        #expect(store.createPlaylist(name: "Chạy bộ")?.name == "Chạy bộ")
        #expect(store.createPlaylist(name: "Chạy bộ") == nil, "a duplicate name")
        #expect(store.createPlaylist(name: "   ") == nil)
        #expect(store.playlists().count == 1)
    }

    @Test("songs keep the order they were added in")
    func playlistOrder() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a"), track("b"), track("c")])
        let playlist = try #require(store.createPlaylist(name: "P"))
        #expect(store.add(track: track("c"), to: playlist.id))
        #expect(store.add(track: track("a"), to: playlist.id))
        #expect(store.add(track: track("b"), to: playlist.id))
        #expect(store.playlistTracks(playlistId: playlist.id).map { $0.uniqueId } == ["c", "a", "b"])
        #expect(store.playlists().first?.trackCount == 3)
    }

    @Test("adding the same song twice does not double it")
    func playlistDedupes() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        let playlist = try #require(store.createPlaylist(name: "P"))
        #expect(store.add(track: track("a"), to: playlist.id))
        #expect(!store.add(track: track("a"), to: playlist.id))
        #expect(store.playlistTracks(playlistId: playlist.id).count == 1)
        #expect(store.playlists(containing: "a") == [playlist.id])
    }

    @Test("taking a song out of one list leaves the other lists alone")
    func removeFromOnePlaylist() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a"), track("b")])
        let first = try #require(store.createPlaylist(name: "P1"))
        let second = try #require(store.createPlaylist(name: "P2"))
        store.add(track: track("a"), to: first.id)
        store.add(track: track("a"), to: second.id)
        store.removeTrack(uniqueId: "a", from: first.id)
        #expect(store.playlistTracks(playlistId: first.id).isEmpty)
        #expect(store.playlistTracks(playlistId: second.id).count == 1)
        #expect(store.playlists(containing: "a") == [second.id])
    }

    @Test("deleting a list does not delete the song it held")
    func deletePlaylistKeepsTracks() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        let playlist = try #require(store.createPlaylist(name: "P"))
        store.add(track: track("a"), to: playlist.id)
        store.deletePlaylist(id: playlist.id)
        #expect(store.playlists().isEmpty)
        #expect(store.playlistTracks(playlistId: playlist.id).isEmpty)
        #expect(store.track(uniqueId: "a") != nil)
    }

    @Test("renaming a list keeps its songs")
    func renamePlaylist() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        let playlist = try #require(store.createPlaylist(name: "Old"))
        store.add(track: track("a"), to: playlist.id)
        #expect(store.renamePlaylist(id: playlist.id, name: "New"))
        #expect(!store.renamePlaylist(id: playlist.id, name: "  "))
        #expect(store.playlists().first?.name == "New")
        #expect(store.playlistTracks(playlistId: playlist.id).count == 1)
    }

    @Test("a list can be given a picture of its own, and take it back off")
    func playlistCoverRoundTrips() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        let playlist = try #require(store.createPlaylist(name: "Chạy bộ"))
        #expect(store.playlists().first?.coverPath == nil)
        #expect(store.setPlaylistCover(id: playlist.id, path: "/tmp/cover.jpg"))
        #expect(store.playlistCoverPath(id: playlist.id) == "/tmp/cover.jpg")
        #expect(store.playlists().first?.coverPath == "/tmp/cover.jpg")
        #expect(store.setPlaylistCover(id: playlist.id, path: nil))
        #expect(store.playlistCoverPath(id: playlist.id) == nil)
        #expect(store.playlists().first?.coverPath == nil)
    }

    /// The database a phone already holds was made by the build before list covers, and
    /// `CREATE TABLE IF NOT EXISTS` will not add a column to the table that build left behind — so
    /// the upgrade has to notice. Written out here in the shape version 1 made.
    @Test("a library from the build before list covers still opens, and gains the column")
    func oldDatabaseGainsTheCoverColumn() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doni-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("library.db").path
        var legacy: OpaquePointer?
        try #require(sqlite3_open(path, &legacy) == SQLITE_OK)
        sqlite3_exec(legacy, "CREATE TABLE playlist (id INTEGER PRIMARY KEY AUTOINCREMENT,"
            + " name TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL)", nil, nil, nil)
        sqlite3_exec(legacy, "INSERT INTO playlist (name, created_at) VALUES ('Cũ', 1)", nil, nil, nil)
        sqlite3_exec(legacy, "PRAGMA user_version = 1", nil, nil, nil)
        sqlite3_close(legacy)

        let store = LibraryStore(path: path)
        defer { store.close() }
        let list = try #require(store.playlists().first)
        #expect(list.name == "Cũ")
        #expect(list.coverPath == nil, "the column is there, and empty")
        #expect(store.setPlaylistCover(id: list.id, path: "/tmp/cover.jpg"))
        #expect(store.playlistCoverPath(id: list.id) == "/tmp/cover.jpg")
    }

    @Test("a channel that goes away takes its songs and their hearts with it")
    func removeChannelCleansUp() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.save(channel: StoreChannel(chatId: -1, username: "a", title: "A"))
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        store.toggleFavorite(uniqueId: "a", segment: nil)
        store.removeChannel(chatId: -1)
        #expect(store.channels().isEmpty)
        #expect(store.tracks().isEmpty)
        #expect(!store.isFavorite("a"))
    }

    @Test("a logout empties the library but not the file it lives in")
    func wipeLeavesTheDatabaseOpen() throws {
        let (store, directory) = try makeStore()
        defer { store.close(); try? FileManager.default.removeItem(at: directory) }
        store.save(channel: StoreChannel(chatId: -1, username: "a", title: "A"))
        store.replaceTracks(chatId: -1, tracks: [track("a")])
        store.toggleFavorite(uniqueId: "a", segment: nil)
        let playlist = try #require(store.createPlaylist(name: "P"))
        store.add(track: track("a"), to: playlist.id)
        store.wipeLibrary()
        #expect(store.channels().isEmpty)
        #expect(store.tracks().isEmpty)
        #expect(store.favorites().isEmpty)
        #expect(store.playlists().isEmpty)
        #expect(store.createPlaylist(name: "Sau khi đăng xuất") != nil, "the tables are still there")
    }
}
