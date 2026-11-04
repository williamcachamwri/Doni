import CryptoKit
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
    /// to say what is in there — so a walk needs no second lookup to start. The picture comes back in
    /// the same answer (`td_api.tl:4080`), so the row knows what to ask for without a request of its
    /// own.
    func add(_ channel: TdChannel) {
        store.save(channel: StoreChannel(chatId: channel.chatId, username: channel.username,
                                         title: channel.title, isIndexed: true,
                                         avatarFileId: channel.photo?.fileId,
                                         avatarUniqueId: channel.photo?.uniqueId))
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
    ///
    /// The published row is patched rather than re-read: a song finishing its download is one row
    /// changing, and `refresh()` re-stats every file the library knows to prove that one of them
    /// exists. The tab that was waiting for the file would wait longer for the count than for it.
    func recordDownload(path: String, uniqueId: String) {
        store.setLocalPath(path, uniqueId: uniqueId)
        downloadedCount = store.downloadedCount()
        downloadedBytes = store.downloadedBytes()
        storedTracks = storedTracks.map { row in
            guard row.uniqueId == uniqueId, row.localPath != path else { return row }
            var filled = row
            filled.localPath = path
            return filled
        }
        // A song that has just landed can now be timed, and it is the only moment it costs nothing:
        // the file is already open on the device and the read is its own header.
        if storedTracks.first(where: { $0.uniqueId == uniqueId })?.duration == nil {
            measure(path: path, uniqueId: uniqueId)
        }
    }

    // MARK: Lengths

    /// A duration the row did not come with, written down.
    ///
    /// Patched into the published rows the way a download path is: the list is showing the row, and
    /// a `refresh()` to prove one number would re-stat every file in the library to do it.
    func recordDuration(_ seconds: Int, uniqueId: String) {
        store.setDuration(seconds, uniqueId: uniqueId)
        storedTracks = storedTracks.map { row in
            guard row.uniqueId == uniqueId, row.duration != seconds else { return row }
            var filled = row
            filled.duration = seconds
            return filled
        }
    }

    /// The rows the phone holds but cannot time, measured. Run once on the way into the library;
    /// after that the store answers nothing and this is free.
    func measureStoredDurations() async {
        for row in store.unmeasuredTracks() {
            guard !Task.isCancelled, let path = row.localPath else { continue }
            guard let seconds = await AudioDuration.seconds(ofPath: path) else { continue }
            recordDuration(seconds, uniqueId: row.uniqueId)
        }
    }

    /// The rows the phone does not hold, timed from the piece of them that a header needs.
    ///
    /// This is the only way a list of songs nobody has ever played can show timestamps for most of
    /// itself: a document post has no duration to read off (`td_api.tl:594`) and TDLib will not open
    /// the container to fill one in. Thirty-two kilobytes per row, asked at cover priority, answers
    /// the question for the two containers these channels actually carry.
    func measureRemoteDurations(with files: TdFileDownloader) async {
        for row in store.unmeasuredTracks(onlyOnDevice: false)
        where row.localPath == nil && row.fileId > 0 {
            guard !Task.isCancelled else { return }
            await probe(row, with: files)
        }
    }

    /// One row's length out of a few kilobytes of it.
    private func probe(_ row: StoreTrack, with files: TdFileDownloader) async {
        guard var head = await files.part(fileId: row.fileId, offset: 0, bytes: Self.headBytes)
        else { return }
        var reading = AudioDuration.read(head: head, totalSize: row.size)
        // An MP3 carrying its picture in the tag hides its first audio frame behind that picture,
        // and the tag says how far. One more ask reaches it, for as long as the picture is a sane
        // size — a megabyte of cover per row is not a price worth paying for a timestamp.
        if case let .headTooSmall(bytes) = reading, bytes > head.count, bytes <= Self.maxHeadBytes {
            guard let deeper = await files.part(fileId: row.fileId, offset: 0, bytes: bytes) else {
                return
            }
            head = deeper
            reading = AudioDuration.read(head: head, totalSize: row.size)
        }
        // An MP4 that was not written for streaming keeps its `mvhd` after the audio, at the end.
        if reading == .tailNeeded, row.size > Self.tailBytes {
            guard let tail = await files.part(fileId: row.fileId, offset: row.size - Self.tailBytes,
                                              bytes: Int(Self.tailBytes)) else { return }
            reading = AudioDuration.read(tail: tail)
        }
        if case let .seconds(seconds) = reading {
            recordDuration(seconds, uniqueId: row.uniqueId)
        }
    }

    /// Enough of a head for an ID3 tag with no art in it, the first frame, and its `Xing`.
    private static let headBytes = 32 * 1024
    /// The biggest tag worth reading a second time.
    private static let maxHeadBytes = 512 * 1024
    /// Enough of a tail for an `mvhd`, which is a hundred and eight bytes. The file's size is the
    /// same unit, so the two are subtractable without a cast at the call.
    private static let tailBytes: Int64 = 64 * 1024

    /// One file, timed, in the background of the screen that asked for it.
    private func measure(path: String, uniqueId: String) {
        Task { [weak self] in
            guard let seconds = await AudioDuration.seconds(ofPath: path) else { return }
            self?.recordDuration(seconds, uniqueId: uniqueId)
        }
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

    // MARK: Channel pictures

    /// The picture a channel wears, decoded through the app's cover cache — a row redraws on every
    /// scroll and the decode is the part worth not doing twice. `nil` until the bytes are on the
    /// phone, which is what tells the row to keep showing its placeholder.
    func avatarImage(of channel: StoreChannel) -> UIImage? {
        guard let path = channel.avatarPath else { return nil }
        return CoverArtwork.shared.image(at: path)
    }

    /// Getting one channel's picture onto the phone, if it is not there already.
    ///
    /// Called from the row that shows it, and it returns having asked for nothing once the copy exists,
    /// so the list of channels costs one `getChat` and one small download per channel the first time
    /// they are looked at and nothing after. What it fetches is `chat.photo`'s `small` variant, a
    /// 160×160 JPEG (`td_api.tl:4080`, `:784`, `:779`) — five times the pixels a 30 pt mark is drawn
    /// at, which is the whole of the difference between this and the glyph it replaces.
    func loadAvatar(of channel: StoreChannel, on session: TelegramSession) async {
        if let path = channel.avatarPath, FileManager.default.fileExists(atPath: path) { return }
        guard let reader = session.reader(), let files = session.covers() else { return }
        guard let photo = try? await reader.photo(chatId: channel.chatId) else { return }
        guard let uniqueId = photo.uniqueId else {
            // A number for the file and no identity for its bytes — TDLib's `fileRemoteUnknown` —
            // leaves nothing safe to file a picture under, so the number is kept and the row asks
            // again next time it is shown.
            store.setChannelAvatar(chatId: channel.chatId, fileId: photo.fileId,
                                   uniqueId: nil, path: nil)
            return
        }
        guard let taken = await files.path(fileId: photo.fileId,
                                           priority: TdFileDownloader.coverPriority) else { return }
        let written = Self.keepPhoto(taken, uniqueId: uniqueId)
        if let written, let previous = channel.avatarPath, previous != written {
            // A channel that changed its picture is a new file rather than an overwrite: the cache
            // this is drawn through is keyed by path, so a path may only ever name one picture.
            try? FileManager.default.removeItem(atPath: previous)
        }
        store.setChannelAvatar(chatId: channel.chatId, fileId: photo.fileId,
                               uniqueId: uniqueId, path: written)
        // The published channels, not the whole library: `refresh()` would re-stat every file on the
        // phone to prove that one picture arrived. Nothing is published when there is no picture.
        if written != nil { channels = store.channels() }
    }

    /// One chat's picture, copied where this app keeps its own files. The copy is what makes the row
    /// instant: TDLib prunes its own caches when the phone wants the room back, and a picture that
    /// lived only there had to be fetched again on every visit.
    private nonisolated static func keepPhoto(_ path: String, uniqueId: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
            return nil
        }
        let url = avatarURL(uniqueId)
        guard !FileManager.default.fileExists(atPath: url.path) else { return url.path }
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    /// The name a picture is kept under: a hash of the file's MTProto identity, which is the same for
    /// the same bytes in every database on every device (`td_api.tl:326`). Hashed because the identity
    /// itself is bytes, and a filename is not allowed to say so.
    private nonisolated static func avatarURL(_ uniqueId: String) -> URL {
        let name = SHA256.hash(data: Data(uniqueId.utf8)).prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return avatarDirectory.appendingPathComponent("\(name).jpg")
    }

    /// Beside the list covers, in the app's private support directory: nothing here is uploaded, and
    /// nothing here is read by anything but this app.
    private nonisolated static var avatarDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Doni/Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: The file

    func remove(channel chatId: Int64) {
        if let path = channels.first(where: { $0.chatId == chatId })?.avatarPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        store.removeChannel(chatId: chatId)
        refresh()
    }

    /// Everything this app put on the phone, thrown away. The session is Keychain's business; the
    /// rows, the hearts and the lists are not.
    func wipe() {
        store.wipeLibrary()
        try? FileManager.default.removeItem(at: Self.coverDirectory)
        try? FileManager.default.removeItem(at: Self.avatarDirectory)
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
                   miniArtwork: track.miniArtwork, coverUniqueId: track.coverUniqueId)
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
