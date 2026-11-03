import Foundation
import SwiftUI
import Support
import TdSession

/// The library on disk.
///
/// TDLib is the only source of a song and it is a slow one: a channel walk is a hundred messages
/// per round trip, so a list built only from the live walk is empty until the network has finished
/// answering. Each page is written down as it lands and read back before the next walk starts,
/// which is what lets the library open with no signal at all.
///
/// A stored `local_path` is trusted only while the file is really there — TDLib empties its own
/// cache when the phone needs room — and `file_id` is TDLib's per-database number
/// (`td_api.tl:326`), stable only while its database is, so a logout takes this file with it.
@MainActor
final class Library: ObservableObject {
    /// One SQLite file per install: the walk writes it, the tabs read it, the player reports into
    /// it. A second instance would be a second connection to the same rows.
    static let shared = Library()

    let store: LibraryStore

    /// What the phone knew when the app last closed, newest first — the rows the list shows before
    /// the walk has brought anything back.
    @Published private(set) var storedTracks: [StoreTrack] = []
    @Published private(set) var favorites: [StoredFavorite] = []
    @Published private(set) var playlists: [StoredPlaylist] = []
    @Published private(set) var channels: [StoreChannel] = []
    @Published private(set) var downloadedCount = 0
    @Published private(set) var trackCount = 0

    init(filename: String = "library.db") {
        store = LibraryStore(path: Self.directory.appendingPathComponent(filename).path)
        refresh()
    }

    /// Every published list and number, re-read. Called after anything that touches the file, so a
    /// heart tapped in one tab shows in the other three without a relaunch.
    func refresh() {
        favorites = store.favorites().map { remembered($0) }
        playlists = store.playlists()
        channels = store.channels()
        downloadedCount = store.downloadedCount()
        trackCount = store.trackCount()
        storedTracks = verified(store.tracks())
    }

    // MARK: The walk

    /// The channel being read. Remembered as selected, because for now the one channel walked is
    /// the one home shows; the picker changes that, not this.
    func remember(_ channel: TdChannel) {
        store.save(channel: StoreChannel(chatId: channel.chatId, username: channel.username,
                                         title: channel.title, isSelected: true))
        store.setSelectedChannel(chatId: channel.chatId)
        refresh()
    }

    /// A page of the walk, written as it arrives. The walk can be stopped halfway, and what it has
    /// read is still the library.
    func remember(page: [TdTrack], chatId: Int64) {
        guard !page.isEmpty else { return }
        store.appendTracks(page.map { stored($0, chatId: chatId) })
    }

    // MARK: Downloads

    /// Where TDLib put the file. Recorded so the row shows as downloaded and a second play of the
    /// same song never asks the network again.
    func recordDownload(path: String, uniqueId: String) {
        store.setLocalPath(path, uniqueId: uniqueId)
        downloadedCount = store.downloadedCount()
    }

    // MARK: Hearts

    func isFavorite(_ uniqueId: String) -> Bool {
        store.isFavorite(uniqueId)
    }

    /// The row's heart, and the list that reads it. A slice is what makes a favourite here
    /// something other than a bookmark, so it travels with the toggle.
    @discardableResult
    func toggleFavorite(_ track: any Playable, segment: ClosedRange<Int>? = nil) -> Bool {
        let on = store.toggleFavorite(uniqueId: track.uniqueId, segment: segment)
        refresh()
        return on
    }

    func setSegment(_ segment: ClosedRange<Int>?, uniqueId: String) {
        store.setFavoriteSegment(segment, uniqueId: uniqueId)
        refresh()
    }

    // MARK: Lists

    @discardableResult
    func createPlaylist(named name: String) -> StoredPlaylist? {
        defer { refresh() }
        return store.createPlaylist(name: name)
    }

    @discardableResult
    func renamePlaylist(id: Int64, name: String) -> Bool {
        defer { refresh() }
        return store.renamePlaylist(id: id, name: name)
    }

    func deletePlaylist(id: Int64) {
        store.deletePlaylist(id: id)
        refresh()
    }

    /// Songs in the order the user put them in, with the files behind them checked.
    func tracks(in playlistId: Int64) -> [StoreTrack] {
        verified(store.playlistTracks(playlistId: playlistId))
    }

    func add(_ track: StoreTrack, to playlistId: Int64) {
        store.add(track: track, to: playlistId)
        refresh()
    }

    func removeTrack(uniqueId: String, from playlistId: Int64) {
        store.removeTrack(uniqueId: uniqueId, from: playlistId)
        refresh()
    }

    func playlists(containing uniqueId: String) -> [Int64] {
        store.playlists(containing: uniqueId)
    }

    // MARK: The file

    func select(channel chatId: Int64) {
        store.setSelectedChannel(chatId: chatId)
        refresh()
    }

    func remove(channel chatId: Int64) {
        store.removeChannel(chatId: chatId)
        refresh()
    }

    /// Everything this app put on the phone, thrown away. The session is Keychain's business; the
    /// rows, the hearts and the lists are not.
    func wipe() {
        store.wipeLibrary()
        refresh()
    }

    // MARK: Rows

    /// TDLib's row written down. A document post has no tags and the store has no caption column,
    /// so the name the list showed live goes into `title` — what the row reads offline is what it
    /// read online. A path is kept only for a file TDLib says it has finished taking.
    private func stored(_ track: TdTrack, chatId: Int64) -> StoreTrack {
        StoreTrack(uniqueId: track.uniqueId, chatId: chatId, messageId: track.messageId,
                   fileId: track.fileId, coverFileId: track.coverFileId,
                   title: track.displayTitle, performer: track.displayPerformer,
                   fileName: track.fileName, duration: track.duration, size: track.size,
                   date: track.date,
                   localPath: track.isDownloaded ? track.localPath : nil,
                   miniArtwork: track.miniArtwork)
    }

    /// Rows are only as good as the files behind them: a path that no longer exists is cleared in
    /// the database too, so the row asks for the song again instead of failing to play it.
    private func verified(_ rows: [StoreTrack]) -> [StoreTrack] {
        rows.map(verified(path:))
    }

    private func verified(path row: StoreTrack) -> StoreTrack {
        guard let path = row.localPath else { return row }
        guard FileManager.default.fileExists(atPath: path) else {
            store.setLocalPath(nil, uniqueId: row.uniqueId)
            var cleared = row
            cleared.localPath = nil
            return cleared
        }
        return row
    }

    private func remembered(_ favorite: StoredFavorite) -> StoredFavorite {
        var fresh = favorite
        fresh.track = verified(path: favorite.track)
        return fresh
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Doni", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
