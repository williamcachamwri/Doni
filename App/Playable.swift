import Foundation
import Support
import TdSession

/// What the player, the artwork cache and a list row all need from a song — whether TDLib handed
/// it over this second or the store remembered it from the last launch.
///
/// The two sources cannot be one type: `TdTrack` carries what a channel post says about a file
/// (its mime type, its caption, who uploaded it) and `StoreTrack` carries what survives a relaunch
/// (`file:id:int32` is TDLib's per-database number, so the id that is stable across both is
/// `file_unique_id`). This is the overlap, and nothing else.
protocol Playable {
    var uniqueId: String { get }
    /// The channel it came from, which is the row the store keys its tracks by.
    var chatId: Int64 { get }
    /// The message it came from, which is also the seed the coverless gradient is picked by.
    var messageId: Int64 { get }
    /// When it was posted — the order the list and the store both read in.
    var date: Int64 { get }
    var fileId: Int { get }
    var localPath: String? { get }
    var isDownloaded: Bool { get }
    var duration: Int? { get }
    var size: Int64 { get }
    var displayTitle: String { get }
    var displayPerformer: String { get }
    /// What the file is called, which is the name a search has to reach for a captionless post.
    var fileName: String { get }
    var fileExtension: String { get }
    var miniArtwork: Data? { get }
    var coverFileId: Int? { get }
}

extension TdTrack: Playable {}

extension StoreTrack: Playable {
    var isDownloaded: Bool { localPath != nil }

    /// The same fallback order the live row uses: tags, then the file name without its extension.
    var displayTitle: String {
        title.isEmpty ? (fileName as NSString).deletingPathExtension : title
    }

    var displayPerformer: String { performer }

    var fileExtension: String { (fileName as NSString).pathExtension.lowercased() }
}

extension StoreTrack {
    /// Any song the app is holding, written down the way the store keeps it, so a track the walk
    /// only just brought back can be put in a list without the list knowing which of the two
    /// sources it came from.
    ///
    /// `displayTitle` and `displayPerformer` rather than the raw fields: what the row showed live is
    /// what the same row has to show after a relaunch.
    init(_ track: any Playable) {
        self.init(uniqueId: track.uniqueId, chatId: track.chatId, messageId: track.messageId,
                  fileId: track.fileId, coverFileId: track.coverFileId,
                  title: track.displayTitle, performer: track.displayPerformer,
                  fileName: track.fileName, duration: track.duration, size: track.size,
                  date: track.date,
                  localPath: track.isDownloaded ? track.localPath : nil,
                  miniArtwork: track.miniArtwork)
    }
}

/// The line under a title. A file with no duration is a document — the pinned schema has no
/// length there — so its extension is the number worth showing.
extension Playable {
    var previewLine: String {
        let bytes = DataSize.string(size)
        let performer = displayPerformer
        guard performer.isEmpty else { return performer + " · " + bytes }
        return duration == nil ? fileExtension.uppercased() + " · " + bytes : bytes
    }

    /// The right-hand column above the state bubble.
    var headline: String {
        if let seconds = MediaClock.duration(duration) { return seconds }
        let ext = fileExtension.uppercased()
        return ext.isEmpty ? "—" : ext
    }
}
