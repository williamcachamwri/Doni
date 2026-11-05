import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import Support
import TdSession
import UIKit

/// The library on disk: every page of a channel walk is written as it lands and read back before the
/// next walk, which is what lets the library open with no signal at all.
///
/// A stored `local_path` is trusted only while the file is really there, since TDLib empties its own
/// cache when the phone needs room, and `file_id` is TDLib's per-database `file:id:int32`
/// (`td_api.tl:326`) — stable only while its database is, so a logout takes this file with it. Rows
/// are keyed by `file_unique_id`, which is the same for the same bytes in every database.
@MainActor
final class Library: ObservableObject {
    /// One SQLite file per install: the walk writes it, the tabs read it, the player reports into
    /// it. A second instance would be a second connection to the same rows.
    static let shared = Library()

    let store: LibraryStore

    /// What the phone knew when the app last closed, newest first — the rows the list shows before
    /// the walk has brought anything back.
    @Published private(set) var storedTracks: [StoreTrack] = []
    /// The songs the phone has heard, most recent first: its own list because the walk sorts by the
    /// post and this shelf sorts by the listen.
    @Published private(set) var recentlyPlayed: [StoreTrack] = []
    @Published private(set) var favorites: [StoredFavorite] = []
    @Published private(set) var playlists: [StoredPlaylist] = []
    @Published private(set) var channels: [StoreChannel] = []
    @Published private(set) var downloadedCount = 0
    @Published private(set) var trackCount = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    /// What the phone really holds, in bytes, measured rather than summed — `nil` until someone asks.
    ///
    /// Published here because two screens quote it, so the disk is walked once and the settings line
    /// never keeps quoting space a cleanup just took back.
    @Published private(set) var disk: DoniStorage?

    /// What the database refused to do, if anything; `nil` means it is answering. A library that
    /// cannot open and an empty one look identical on screen, and only one of them is the user's fault.
    @Published private(set) var storeFailure: String?

    init(filename: String = "library.db") {
        self.filename = filename
        store = LibraryStore(path: Self.supportDirectory.appendingPathComponent(filename).path)
        if UserDefaults.standard.bool(forKey: Self.eraseKey) {
            // A sign-out the app did not finish: nothing is read until the files are gone, or the old
            // library shows for a run loop before being thrown away.
            Task { await self.resumeWipe() }
        } else {
            refresh()
        }
        // Once per launch, and off the main thread: the rows say which files they expect, and only
        // the disk knows whether they are still there.
        Task { await self.verifyFiles() }
    }

    /// Finishing what `wipe` could not finish, then reading what is actually left.
    private func resumeWipe() async {
        store.close()
        let left = await Self.eraseOwnFiles(named: filename)
        UserDefaults.standard.set(!left.isEmpty, forKey: Self.eraseKey)
        store.reopen()
        refresh()
    }

    /// The name `wipe` unlinks. Kept because the file is the thing that has to go, not its rows.
    private let filename: String

    /// Every published list and number, re-read. Called after anything that touches the file, so a
    /// heart tapped in one tab shows in the other three without a relaunch.
    /// The file a row promised is no longer usable: the row stops claiming it, so the next tap fetches
    /// it again.
    func forgetLocalPath(uniqueId: String) {
        store.setLocalPath(nil, uniqueId: uniqueId)
        storedTracks = storedTracks.map { row in
            guard row.uniqueId == uniqueId, row.localPath != nil else { return row }
            var cleared = row
            cleared.localPath = nil
            return cleared
        }
        downloadedCount = store.downloadedCount()
        downloadedBytes = store.downloadedBytes()
    }

    func refresh() {
        storeFailure = store.failure
        favorites = store.favorites().map { remembered($0) }
        playlists = store.playlists()
        channels = store.channels()
        downloadedCount = store.downloadedCount()
        downloadedBytes = store.downloadedBytes()
        trackCount = store.trackCount()
        storedTracks = store.tracks()
        recentlyPlayed = store.recentlyPlayed(limit: Self.recentLimit)
    }

    /// Only the favourites, which is what a heart or a cut actually changed: `refresh` re-reads every
    /// row and every picture, which is far too much to pay for a tap.
    func refreshFavorites() {
        storeFailure = store.failure
        favorites = store.favorites()
    }

    /// Checking the claims the rows make about files on the phone: one `stat` per row with a path, off
    /// the main thread, once per launch.
    ///
    /// A file that disappears while the app is open is caught by the player failing to open it, which
    /// forgets the path on the spot.
    func verifyFiles() async {
        let store = self.store
        let stale = await Task.detached(priority: .utility) { () -> [String] in
            let missing = store.localPaths()
                .filter { !FileManager.default.fileExists(atPath: $0.path) }
                .map(\.uniqueId)
            for id in missing { store.setLocalPath(nil, uniqueId: id) }
            return missing
        }.value
        guard !stale.isEmpty, !Task.isCancelled else { return }
        refresh()
    }

    // MARK: The walk

    /// A channel on the allow-list. Its chat id is already resolved by the screen that added it, so a
    /// walk needs no second lookup, and the picture comes back in the same answer (`td_api.tl:4080`).
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

    /// A page of the account's own chat, written down and marked as the listener's own.
    ///
    /// Not `remember(page:)`, which files a song under the channel that posted it: Saved Messages
    /// holds songs a dozen channels posted, and the flag keeps both lists.
    func rememberCloud(page: [TdTrack], chatId: Int64) {
        guard !page.isEmpty else { return }
        store.saveCloud(page.map { stored($0, chatId: chatId) })
    }

    /// One song a channel posted while the app was open, written down and published: a post landing
    /// with no walk running has nobody else to report it. Patched rather than `refresh()`ed, which
    /// would re-stat every file on the phone to prove one row appeared.
    ///
    /// Timed too when the post has no length, because a document carries no duration
    /// (`td_api.tl:594`).
    func ingest(_ track: TdTrack, with files: TdFileDownloader?) {
        let fresh = stored(track, chatId: track.chatId)
        store.appendTracks([fresh])
        trackCount = store.trackCount()
        var written = fresh
        if let index = storedTracks.firstIndex(where: { $0.uniqueId == fresh.uniqueId }) {
            // The published row has to agree with the stored one, whose `duration` and `local_path`
            // the upsert below COALESCEs rather than clears.
            written.duration = fresh.duration ?? storedTracks[index].duration
            written.localPath = fresh.localPath ?? storedTracks[index].localPath
            storedTracks[index] = written
        } else {
            // The store's own order is newest first, and a post that has just landed is the newest.
            storedTracks.insert(written, at: 0)
        }
        guard written.duration == nil, written.fileId > 0, let files else { return }
        Task { [weak self] in
            await self?.probe(written, with: files)
        }
    }

    // MARK: Files the user brings

    /// A song the user picked out of the Files app, taken into the library.
    ///
    /// The bytes are copied rather than read where they lie: a security-scoped URL is only good while
    /// this app holds it, and an iCloud item is a file with no audio until the system fetches it. The
    /// copy never leaves the phone.
    ///
    /// Published the way a live arrival is: `refresh()` would re-stat every file to prove one arrived.
    func importMusic(from url: URL) async -> Result<StoreTrack, MusicImportFailure> {
        switch await Self.take(url) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let row):
            store.appendTracks([row])
            if let failure = store.failure {
                print("library store rejected import: \(failure)")
            }
            trackCount = store.trackCount()
            downloadedCount = store.downloadedCount()
            downloadedBytes = store.downloadedBytes()
            if let index = storedTracks.firstIndex(where: { $0.uniqueId == row.uniqueId }) {
                storedTracks[index] = row
            } else {
                storedTracks.insert(row, at: 0)
            }
            return .success(row)
        }
    }

    /// A song the user imported, taken out again: the row, whatever pointed at it, and the bytes the
    /// app copied. The one delete this library can honour outright — no walk re-indexes it.
    func removeLocal(_ track: StoreTrack) {
        if let path = track.localPath { try? FileManager.default.removeItem(atPath: path) }
        store.removeTrack(uniqueId: track.uniqueId)
        refresh()
    }

    /// One file, hashed and copied and written down, off the main thread: a 40 MB song is ~100 ms of
    /// hashing and another ~100 ms of copying.
    ///
    /// The read goes through `NSFileCoordinator`, not straight at the URL: a picker's URL is a promise
    /// about a file, and an item still parked in iCloud is a regular file with no bytes behind it
    /// until coordination makes it readable. `isReadableFile` says true; `FileHandle` refuses.
    ///
    /// Every step reports which one failed, rather than collapsing them into `nil`.
    private nonisolated static func take(_ url: URL) async -> Result<StoreTrack, MusicImportFailure> {
        // Only a Files-app URL needs this, and it answers false for a file the app already owns, so
        // the pair is entered on the flag. Held until this function returns: giving the permission up
        // halfway through a copy is a failed copy.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        print("file take \(url.lastPathComponent) scoped=\(scoped)")
        let copied: Result<(hash: String, kept: String, bytes: Int64), MusicImportFailure> =
            await Task.detached(priority: .userInitiated) {
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var taken: Result<(hash: String, kept: String, bytes: Int64),
                                  MusicImportFailure> = .failure(.unreadable)
                coordinator.coordinate(readingItemAt: url,
                                       options: [.withoutChanges],
                                       error: &coordinationError) { readable in
                    taken = read(readable, namedBy: url)
                }
                if case .failure = taken, let coordinationError {
                    print("file coordination refused \(url.lastPathComponent): \(coordinationError)")
                }
                return taken
            }.value

        if case .failure(let reason) = copied { return .failure(reason) }
        guard case .success(let file) = copied else { return .failure(.unreadable) }
        // An empty title is not a failure: the row falls back to the file's name without its
        // extension. Both reads come after the coordination, on the app's own copy.
        let tags = await AudioTags.read(path: file.kept)
        return .success(StoreTrack(uniqueId: file.hash, chatId: 0, messageId: 0, fileId: 0,
                                   title: tags.title, performer: tags.performer,
                                   fileName: url.lastPathComponent,
                                   duration: await AudioDuration.seconds(ofPath: file.kept),
                                   size: file.bytes, date: Int64(Date().timeIntervalSince1970),
                                   localPath: file.kept))
    }

    /// The coordinated file, hashed and copied into the library. `namedBy` is the URL the picker
    /// handed over, so the row keeps the name the user recognised rather than the one the
    /// coordinator made for its copy.
    private nonisolated static func read(_ url: URL, namedBy original: URL)
    -> Result<(hash: String, kept: String, bytes: Int64), MusicImportFailure> {
        guard isAudioFile(url) else {
            print("file not a regular audio file: \(original.lastPathComponent)")
            return .failure(.notAFile)
        }
        guard let hash = fingerprint(url) else {
            return .failure(.unreadable)
        }
        guard let kept = copy(url, named: hash) else {
            print("file copy failed: \(original.lastPathComponent)")
            return .failure(.unwritable)
        }
        let bytes = size(ofPath: kept)
        guard bytes > 0 else {
            print("file copy empty: \(original.lastPathComponent)")
            return .failure(.empty)
        }
        print("file copied: \(original.lastPathComponent) bytes=\(bytes)")
        return .success((hash, kept, bytes))
    }

    /// The name a file is kept under and the id its row is stored by: SHA-256 of its own bytes.
    ///
    /// MTProto's `file_unique_id` (`td_api.tl:784`) says two Telegram songs are the same file, and
    /// imported bytes never went through Telegram, so the content hash is the identity: the same MP3
    /// picked twice updates its row instead of spending the space again. Chunked at 1 MB because a
    /// one-hour set is 140 MB and `Data(contentsOf:)` would hold all of it at once.
    private nonisolated static func fingerprint(_ url: URL) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while true {
                let chunk = try handle.read(upToCount: Self.fingerprintChunk)
                if let chunk, !chunk.isEmpty {
                    hasher.update(data: chunk)
                } else {
                    break
                }
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            print("file fingerprint error for \(url.path): \(error)")
            let exists = FileManager.default.fileExists(atPath: url.path)
            let isReadable = FileManager.default.isReadableFile(atPath: url.path)
            print("file status at path: exists=\(exists) readable=\(isReadable)")
            return nil
        }
    }

    private nonisolated static let fingerprintChunk = 1024 * 1024

    /// A file rather than a directory, a symlink or whatever else the picker was pointed at.
    ///
    /// Asked of the URL, not the path: the Files app reads through the permission attached to the URL,
    /// and the path form can be refused while the URL itself is fine.
    private nonisolated static func isAudioFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    /// The bytes read through the URL and written out again, rather than handed to `copyItem`.
    ///
    /// `copyItem` is FileManager's fast path, and it does not travel through the permission a picked
    /// URL carries: an MP3 in the phone's own Downloads opens with a file handle and hashes, then
    /// refuses to be copied. Reading is what the permission is for, so this reads.
    private nonisolated static func copy(_ url: URL, named hash: String) -> String? {
        let destination = musicDirectory.appendingPathComponent(hash)
            .appendingPathExtension(url.pathExtension)
        if FileManager.default.fileExists(atPath: destination.path) { return destination.path }
        guard let source = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? source.close() }
        do {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                return nil
            }
            let target = try FileHandle(forWritingTo: destination)
            defer { try? target.close() }
            while true {
                guard let chunk = try source.read(upToCount: fingerprintChunk) else {
                    throw CocoaError(.fileReadUnknown)
                }
                if chunk.isEmpty { break }
                try target.write(contentsOf: chunk)
            }
            return destination.path
        } catch {
            // Half a song on the phone is worse than none: it would hash to the same id next time
            // and be found already there.
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }

    private nonisolated static func size(ofPath path: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: Downloads

    /// Where TDLib put the file, so the row shows as downloaded and a second play never asks again.
    ///
    /// The published row is patched rather than re-read: `refresh()` re-stats every file the library
    /// knows just to prove one of them exists.
    /// The disk the music cache may take, and the number the sweep is measured against.
    ///
    /// Two gigabytes is about twelve hour-long sets and below the point where iOS starts freeing a
    /// 128 GB device itself; it is a preference because a phone shared with video wants less.
    @Published var cacheQuota: Int64 =
        (UserDefaults.standard.object(forKey: Library.quotaKey) as? NSNumber)?.int64Value
        ?? Library.defaultQuota {
        didSet { UserDefaults.standard.set(cacheQuota, forKey: Self.quotaKey) }
    }
    private static let quotaKey = "cache.quota.bytes"
    private static let defaultQuota: Int64 = 2 * 1024 * 1024 * 1024

    /// How many plays the shelf at the head of Home is allowed to hold: one strip's worth of cards,
    /// which is also how many the other shelves cut themselves at.
    private static let recentLimit = 20

    /// When a song was heard, and what was heard.
    ///
    /// The whole row, not just its id: a song can be played from a message the walk has not written
    /// down yet, and an update over no row never reaches the shelf. The row is read back from the
    /// store, so the card wears what the store kept.
    func recordPlay(_ track: any Playable) {
        let seconds = Int64(Date().timeIntervalSince1970)
        let row = StoreTrack(track)
        store.markPlayed(row, at: seconds)
        var fresh = recentlyPlayed.filter { $0.uniqueId != row.uniqueId }
        fresh.insert(store.track(uniqueId: row.uniqueId) ?? row, at: 0)
        recentlyPlayed = Array(fresh.prefix(Self.recentLimit))
    }

    /// Give the cache back until it fits the quota, least-heard first.
    ///
    /// Eviction is whole-file because TDLib offers nothing else — `deleteFile` (`td_api.tl:15052`)
    /// gives up a file, not a part of one — so `local_path` is cleared in the same breath the bytes
    /// are freed: a path left behind after its bytes are gone is an unplayable row.
    ///
    /// The song under the playhead is never a victim.
    func trimCache(with files: TdFileDownloader, keeping: String?) async -> Int {
        let rows = store.cacheRows()
        let entries = rows.map {
            AudioCacheRow(uniqueId: $0.uniqueId, bytes: $0.size, isComplete: $0.isComplete,
                          lastPlayedAt: $0.lastPlayedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                          isCurrent: $0.uniqueId == keeping)
        }
        let victims = AudioCachePolicy.evictions(entries, quotaBytes: cacheQuota)
        guard !victims.isEmpty else { return 0 }
        let byId = Dictionary(rows.map { ($0.uniqueId, $0) }, uniquingKeysWith: { first, _ in first })
        var freed = 0
        for uniqueId in victims {
            guard let row = byId[uniqueId] else { continue }
            if await files.remove(TdFile(fileId: row.fileId, uniqueId: row.uniqueId)) {
                store.setLocalPath(nil, uniqueId: uniqueId)
                freed += 1
                print("cache evicted \(uniqueId) size=\(row.size)")
            }
        }
        if freed > 0 { refresh() }
        return freed
    }

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
        // the file is already open and the read is its own header.
        if storedTracks.first(where: { $0.uniqueId == uniqueId })?.duration == nil {
            measure(path: path, uniqueId: uniqueId)
        }
    }

    /// Walking the disk and publishing what was found: called when the settings screen appears and
    /// after anything that throws bytes away. The walk is detached at utility priority
    /// (`StorageTally`), so it is safe to fire from a `.task` on a scrolling screen.
    func remeasureDisk() async {
        disk = await StorageTally.measure()
    }

    /// Releasing the songs Telegram can hand back, and counting how many went.
    ///
    /// TDLib is asked first because it keeps its own record: bytes deleted from under it leave a row
    /// saying "downloaded" that it keeps answering `downloadFile` with.
    ///
    /// Imported files are never in this loop — no server holds a copy, and `fileId` 0 is TDLib's way
    /// of saying it never heard of the bytes.
    func clearTelegramDownloads(with files: TdFileDownloader) async -> Int {
        var released = 0
        for row in storedTracks where row.isDownloaded && !row.isLocal && row.fileId != 0 {
            guard await files.remove(TdFile(audio: row)) else { continue }
            store.setLocalPath(nil, uniqueId: row.uniqueId)
            released += 1
        }
        refresh()
        return released
    }

    // MARK: Lengths

    /// A duration the row did not come with, written down.
    ///
    /// Patched into the published rows like a download path: a `refresh()` to prove one number would
    /// re-stat every file in the library.
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
    /// A document post has no duration to read off (`td_api.tl:594`) and TDLib will not open the
    /// container: 32 KiB per row at cover priority answers it for the two containers these channels
    /// carry.
    func measureRemoteDurations(with files: TdFileDownloader) async {
        for row in store.unmeasuredTracks(onlyOnDevice: false)
        where row.localPath == nil && row.fileId > 0 {
            guard !Task.isCancelled else { return }
            await probe(row, with: files)
        }
    }

    /// One row's length out of a few kilobytes of it.
    private func probe(_ row: StoreTrack, with files: TdFileDownloader) async {
        let file = TdFile(audio: row)
        guard var head = await files.part(file, offset: 0, bytes: Self.headBytes)
        else { return }
        var reading = AudioDuration.read(head: head, totalSize: row.size)
        // An MP3 with its picture in the tag hides the first audio frame behind it, and the tag says
        // how far: one more ask reaches it, up to `maxHeadBytes` per row.
        if case let .headTooSmall(bytes) = reading, bytes > head.count, bytes <= Self.maxHeadBytes {
            guard let deeper = await files.part(file, offset: 0, bytes: bytes) else {
                return
            }
            head = deeper
            reading = AudioDuration.read(head: head, totalSize: row.size)
        }
        // An MP4 that was not written for streaming keeps its `mvhd` after the audio, at the end.
        if reading == .tailNeeded, row.size > Self.tailBytes {
            guard let tail = await files.part(file, offset: row.size - Self.tailBytes,
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
        refreshFavorites()
        return on
    }

    func setSegment(_ segment: ClosedRange<Int>?, uniqueId: String) {
        store.setFavoriteSegment(segment, uniqueId: uniqueId)
        refreshFavorites()
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

    /// The head of a list, which is the only artwork a list here has. Unverified: a cover does not care
    /// whether the file is still on the device, and this is drawn per row.
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

    /// Puts a picture the user chose on a list, and throws away the one it wore. The resize happens off
    /// the main thread: a twelve megapixel JPEG is ~100 ms of decoding.
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

    /// The picture a channel wears, decoded through the app's cover cache: a row redraws on every
    /// scroll, so the decode is the part worth not doing twice. `nil` until the bytes are on the
    /// phone, which is what keeps the row on its placeholder.
    func avatarImage(of channel: StoreChannel) -> UIImage? {
        guard let path = channel.avatarPath else { return nil }
        return CoverArtwork.shared.image(at: path)
    }

    /// Getting one channel's picture onto the phone, if it is not there already: called from the row
    /// that shows it, asking nothing once the copy exists, so a channel costs one `getChat` and one
    /// small download the first time it is looked at and nothing after.
    ///
    /// What it fetches is `chat.photo`'s `small` variant, a 160×160 JPEG (`td_api.tl:4080`, `:784`,
    /// `:779`) — five times the pixels a 30 pt mark is drawn at.
    func loadAvatar(of channel: StoreChannel, on session: TelegramSession) async {
        if let path = channel.avatarPath, FileManager.default.fileExists(atPath: path) { return }
        guard let reader = session.reader(), let files = session.covers() else { return }
        guard let photo = try? await reader.photo(chatId: channel.chatId) else { return }
        guard let uniqueId = photo.uniqueId else {
            // A file number with no identity for its bytes — TDLib's `fileRemoteUnknown` — is nothing
            // safe to file a picture under, so the row asks again next time it is shown.
            store.setChannelAvatar(chatId: channel.chatId, fileId: photo.fileId,
                                   uniqueId: nil, path: nil)
            return
        }
        guard let taken = await files.path(TdFile(fileId: photo.fileId, uniqueId: uniqueId),
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

    /// One chat's picture, copied where this app keeps its own files: TDLib prunes its caches when the
    /// phone wants room, so a picture kept only there is refetched on every visit.
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
    /// the same bytes in every database on every device (`td_api.tl:326`). Hashed because that
    /// identity is raw bytes and a filename may not say so.
    private nonisolated static func avatarURL(_ uniqueId: String) -> URL {
        let name = SHA256.hash(data: Data(uniqueId.utf8)).prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return avatarDirectory.appendingPathComponent("\(name).jpg")
    }

    /// Beside the list covers, in the app's private support directory: nothing here is uploaded, and
    /// nothing here is read by anything but this app.
    nonisolated static var avatarDirectory: URL {
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

    /// Everything this app put on the phone, thrown away — the file, not only its rows.
    ///
    /// Rows are not enough: SQLite keeps the pages it deleted until something overwrites them, so a
    /// sign-out that only ran DELETE leaves the library readable. The connection closes, the database
    /// and its `-wal`/`-shm` are unlinked, and an empty one opens in their place.
    ///
    /// The session itself is Keychain's business, and TDLib's directory goes with its client.
    ///
    /// `false` means something is still on the phone that should not be; the erase flag finishes it on
    /// the next launch.
    @discardableResult
    func wipe() async -> Bool {
        store.close()
        let left = await Self.eraseOwnFiles(named: filename)
        store.reopen()
        refresh()
        guard !left.isEmpty else { return true }
        UserDefaults.standard.set(true, forKey: Self.eraseKey)
        return false
    }

    /// The same promise the session keeps for its own directory: an interrupted deletion is not
    /// forgotten, it is finished the next time the app starts.
    private static let eraseKey = "library.eraseOnLaunch"

    /// Throwing away the library's files and reporting what refused to go.
    ///
    /// A file TDLib or the player still holds open comes back on the first try, so what is left gets
    /// one more pass 200 ms later. Several hundred megabytes, so this is detached and the wait is a
    /// task rather than a thread.
    private nonisolated static func eraseOwnFiles(named filename: String) async -> [URL] {
        let targets = [Self.supportDirectory.appendingPathComponent(filename)]
            + ["-wal", "-shm"].map {
                Self.supportDirectory.appendingPathComponent(filename + $0)
            }
            + [coverDirectory, avatarDirectory, musicDirectory]
        return await Task.detached(priority: .utility) {
            var left = targets
            for attempt in 0..<2 {
                if attempt > 0 {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                for url in left where FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
                left = left.filter { FileManager.default.fileExists(atPath: $0.path) }
                if left.isEmpty { break }
            }
            return left
        }.value
    }

    // MARK: Rows

    /// TDLib's row written down. A document post has no tags and the store has no caption column, so
    /// the name the list showed live goes into `title`. A path is kept only for a finished file.
    private func stored(_ track: TdTrack, chatId: Int64) -> StoreTrack {
        StoreTrack(uniqueId: track.uniqueId, chatId: chatId, messageId: track.messageId,
                   fileId: track.fileId, coverFileId: track.coverFileId,
                   title: track.displayTitle, performer: track.displayPerformer,
                   fileName: track.fileName, duration: track.duration, size: track.size,
                   date: track.date,
                   localPath: track.isDownloaded ? track.localPath : nil,
                   miniArtwork: track.miniArtwork, coverUniqueId: track.coverUniqueId,
                   mimeType: track.mimeType)
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

    /// The folder this app's own files live in, and the one every path below hangs off: the storage
    /// screen measures the disk rather than the rows, which only record what the app meant to keep.
    nonisolated static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Doni", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Where a list's own picture lives: beside the database, in the app's private support directory,
    /// never uploaded — the only reader of a chosen cover is this app.
    nonisolated static var coverDirectory: URL {
        let url = supportDirectory.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Where a file the user brought in is kept: Application Support, never `Caches` and never TDLib's
    /// directory — both are free to be pruned, and an imported song has no copy anywhere to refetch.
    nonisolated static var musicDirectory: URL {
        let url = supportDirectory.appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// One file per choice rather than one per list, so a path names exactly one picture: the decoded
    /// cover cache is keyed by path, so an overwrite would keep drawing the old cover.
    private static func newCoverURL(for playlistId: Int64) -> URL {
        coverDirectory.appendingPathComponent("playlist-\(playlistId)-\(UUID().uuidString).jpg")
    }

    /// The widest a list's cover is drawn: the detail hero caps at 300 pt
    /// (`MusicPlaylistMetrics`/`MusicArtworkMetrics.heroSide`), so 600 px is that at a 2× screen and
    /// nothing bigger is ever read from this file.
    private static let coverSide = 600

    /// Resize while reading, not after: `kCGImageSourceThumbnailMaxPixelSize` only means anything to
    /// `CGImageSourceCreateThumbnailAtIndex`. `kCGImageSourceCreateThumbnailWithTransform` is what
    /// honours the photo's own EXIF orientation, without which a portrait is written sideways.
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

/// Why a file the user picked did not become a song, in words the screen can show: each step reports
/// its own failure rather than every step answering the same `nil`.
enum MusicImportFailure: Error {
    case notAFile, unreadable, unwritable, empty

    var message: String {
        switch self {
        case .notAFile: return "không phải một tệp"
        case .unreadable: return "không mở được tệp"
        case .unwritable: return "không ghi được vào thư mục nhạc"
        case .empty: return "tệp rỗng"
        }
    }
}
