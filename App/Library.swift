import Foundation
import ImageIO
import SwiftUI
import Support
import TdSession
import UIKit

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
    @Published private(set) var downloadedBytes: Int64 = 0

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
        downloadedBytes = store.downloadedBytes()
        trackCount = store.trackCount()
        storedTracks = verified(store.tracks())
    }

    // MARK: The walk

    /// A channel on the allow-list, remembered from the link or the chat list it was picked out of.
    /// The chat id is already resolved by then — the screen that adds a channel has read a page of it
    /// to say what is in there — so a walk needs no second lookup to start.
    func add(_ channel: TdChannel) {
        store.save(channel: StoreChannel(chatId: channel.chatId, username: channel.username,
                                         title: channel.title, isIndexed: true))
        refresh()
    }

    /// Opting a channel into the index, or back out of it. Out leaves its rows on the phone: a
    /// channel switched off is a channel not being read, not a channel deleted.
    func setIndexed(_ chatId: Int64, on: Bool) {
        store.setChannel(chatId: chatId, indexed: on)
        refresh()
    }

    /// The channels the walk reads.
    var indexedChannels: [StoreChannel] {
        channels.filter(\.isIndexed)
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
        downloadedBytes = store.downloadedBytes()
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
        removeCover(playlistId: id)
        store.deletePlaylist(id: id)
        refresh()
    }

    /// Songs in the order the user put them in, with the files behind them checked.
    func tracks(in playlistId: Int64) -> [StoreTrack] {
        verified(store.playlistTracks(playlistId: playlistId))
    }

    /// The head of a list, which is the only artwork a list here has. Unverified on purpose: a
    /// cover does not care whether the file is still on the device, and the caller draws this one
    /// per row rather than once per screen.
    func firstTrack(in playlistId: Int64) -> StoreTrack? {
        store.playlistTracks(playlistId: playlistId).first
    }

    /// Putting a song in a list writes the song too — `LibraryStore.add` upserts it first, because a
    /// playlist outlives the walk that found the song inside it.
    func add(_ track: any Playable, to playlistId: Int64) {
        store.add(track: StoreTrack(track), to: playlistId)
        refresh()
    }

    func removeTrack(uniqueId: String, from playlistId: Int64) {
        store.removeTrack(uniqueId: uniqueId, from: playlistId)
        refresh()
    }

    func playlists(containing uniqueId: String) -> [Int64] {
        store.playlists(containing: uniqueId)
    }

    // MARK: List covers

    /// Puts a picture the user chose on a list, and throws away the one it wore. The bytes come from
    /// the photo library at camera size, so the resize happens off the main thread — a twelve
    /// megapixel JPEG is a hundred milliseconds of decoding, and the app is being asked to play
    /// music while it happens.
    func setCover(_ data: Data, for playlistId: Int64) async -> Bool {
        guard let written = await Self.encode(data, to: Self.newCoverURL(for: playlistId),
                                              side: Self.coverSide) else {
            return false
        }
        removeCover(playlistId: playlistId)
        let stored = store.setPlaylistCover(id: playlistId, path: written)
        refresh()
        return stored
    }

    /// Back to the list's own artwork, which is its first song's cover.
    func clearCover(playlistId: Int64) {
        removeCover(playlistId: playlistId)
        _ = store.setPlaylistCover(id: playlistId, path: nil)
        refresh()
    }

    private func removeCover(playlistId: Int64) {
        guard let path = store.playlistCoverPath(id: playlistId) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: The file

    func remove(channel chatId: Int64) {
        store.removeChannel(chatId: chatId)
        refresh()
    }

    /// Everything this app put on the phone, thrown away. The session is Keychain's business; the
    /// rows, the hearts and the lists are not.
    func wipe() {
        store.wipeLibrary()
        try? FileManager.default.removeItem(at: Self.coverDirectory)
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

    /// Where a list's own picture lives: beside the database, in the app's private support
    /// directory. Nothing here is uploaded anywhere — a chosen cover is a file on this phone and
    /// the only reader of it is this app.
    private static var coverDirectory: URL {
        let url = directory.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// One file per choice rather than one file per list, so a path names exactly one picture. The
    /// cache that holds decoded covers is keyed by path: a list that changed its cover would
    /// otherwise go on drawing the old one until the app relaunched.
    private static func newCoverURL(for playlistId: Int64) -> URL {
        coverDirectory.appendingPathComponent("playlist-\(playlistId)-\(UUID().uuidString).jpg")
    }

    /// The widest a list's cover is drawn: the detail hero caps at 300 pt
    /// (`MusicPlaylistMetrics`/`MusicArtworkMetrics.heroSide`), so 600 px is that at a 2× screen and
    /// nothing bigger is ever read from this file.
    private static let coverSide = 600

    /// Resize while reading, not after: `kCGImageSourceThumbnailMaxPixelSize` only means anything to
    /// `CGImageSourceCreateThumbnailAtIndex`, the same key that keeps `CoverArtwork`'s decodes cheap.
    /// `kCGImageSourceCreateThumbnailWithTransform` is what honours the photo's own EXIF orientation,
    /// without which a portrait shot is written sideways.
    private nonisolated static func encode(_ data: Data, to url: URL, side: Int) async -> String? {
        let written: Bool = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData,
                                                            [kCGImageSourceShouldCache: false]
                                                                as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceShouldCacheImmediately: true,
                      kCGImageSourceThumbnailMaxPixelSize: side,
                  ] as CFDictionary)
            else { return false }
            guard let bytes = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) else {
                return false
            }
            do {
                try bytes.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }.value
        return written ? url.path : nil
    }
}
