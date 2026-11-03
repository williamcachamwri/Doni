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

    init(filename: String = "library.db") {
        store = LibraryStore(path: Self.directory.appendingPathComponent(filename).path)
        refresh()
    }

    // MARK: The walk

    /// The channel being read. Remembered as selected, because for now the one channel walked is
    /// the one home shows; the picker changes that, not this.
    func remember(_ channel: TdChannel) {
        store.save(channel: StoreChannel(chatId: channel.chatId, username: channel.username,
                                         title: channel.title, isSelected: true))
        store.setSelectedChannel(chatId: channel.chatId)
    }

    /// A page of the walk, written as it arrives. The walk can be stopped halfway, and what it has
    /// read is still the library.
    func remember(page: [TdTrack], chatId: Int64) {
        guard !page.isEmpty else { return }
        store.appendTracks(page.map { stored($0, chatId: chatId) })
    }

    func refresh() {
        storedTracks = verified(store.tracks())
    }

    // MARK: Downloads

    /// Where TDLib put the file. Recorded so the row shows as downloaded and a second play of the
    /// same song never asks the network again.
    func recordDownload(path: String, uniqueId: String) {
        store.setLocalPath(path, uniqueId: uniqueId)
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

    /// The rows are only as good as the files behind them: a path that no longer exists is cleared
    /// in the database too, so the row asks for the song again instead of failing to play it.
    private func verified(_ rows: [StoreTrack]) -> [StoreTrack] {
        let reader = FileManager.default
        return rows.map { row in
            guard let path = row.localPath else { return row }
            guard reader.fileExists(atPath: path) else {
                store.setLocalPath(nil, uniqueId: row.uniqueId)
                var cleared = row
                cleared.localPath = nil
                return cleared
            }
            return row
        }
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Doni", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
