import Foundation

/// One playable thing a channel message carries.
///
/// The shape comes from the pinned schema: a music channel posts the same song
/// as `messageAudio` (uploaded as audio, so it has tags) or as
/// `messageDocument` (uploaded as a file, so it has only a name and a size), and
/// the dedupe key both of them share is `file.remote.unique_id` — TDLib's
/// `file:id:int32` (`td_api.tl:326`) is per-database, while MTProto's
/// `file_unique_id` is what repeats across messages, channels and re-uploads.
public struct TdTrack: Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        /// `messageAudio` — has duration and, when the uploader set them, title and performer tags.
        case audio
        /// `messageDocument` — a bare file; only a name, a mime type and a size.
        case document
        /// `messageVoiceNote` — a round voice message; playable, but not a song.
        case voiceNote
    }

    public let messageId: Int64
    public let chatId: Int64
    public let date: Int64
    public let origin: Origin
    public let fileId: Int
    public let uniqueId: String
    public let title: String
    public let performer: String
    public let fileName: String
    public let mimeType: String
    public let caption: String
    /// Bytes on the server; `expected_size` while TDLib has not seen the file yet.
    public let size: Int64
    /// Seconds, `nil` for a document — the schema has no duration there, so only
    /// the player can measure it.
    public let duration: Int?
    /// Set once TDLib has the file on the device.
    public let localPath: String?
    public let isDownloaded: Bool
    /// TDLib's `minithumbnail` for the cover tag: a few hundred bytes of JPEG the
    /// message itself carries, so the list can show real artwork without asking for
    /// a file. `nil` when the post has no cover, which is a third of a real channel.
    public let miniArtwork: Data?

    /// `message` is a `message` object; nil for anything that is not a file the
    /// app can play.
    public init?(message: TdJSON) {
        guard let content = message["content"], let chatId = message["chat_id"]?.int,
              let messageId = message["id"]?.int
        else { return nil }

        let origin: Origin
        let file: TdJSON?
        let title: String
        let performer: String
        let fileName: String
        let mimeType: String
        let caption: String
        let duration: Int?
        let miniArtwork: Data?

        switch content.type {
        case "messageAudio":
            origin = .audio
            let audio = content["audio"]
            file = audio?["audio"]
            title = audio?["title"]?.string ?? ""
            performer = audio?["performer"]?.string ?? ""
            fileName = audio?["file_name"]?.string ?? ""
            mimeType = audio?["mime_type"]?.string ?? ""
            caption = content["caption"]?["text"]?.string ?? ""
            duration = Int(audio?["duration"]?.int ?? 0)
            // TDLib serialises `bytes` as base64; this is the only artwork that comes
            // with the message rather than as a file that has to be fetched
            // (`td_api.tl:583`, `audio.album_cover_minithumbnail`). A document's own
            // minithumbnail is a drawn file icon, so it is not artwork and stays unread.
            let encodedArtwork = audio?["album_cover_minithumbnail"]?["data"]?.string
            miniArtwork = encodedArtwork.flatMap { Data(base64Encoded: $0) }
        case "messageDocument":
            origin = .document
            let document = content["document"]
            file = document?["document"]
            title = ""
            performer = ""
            fileName = document?["file_name"]?.string ?? ""
            mimeType = document?["mime_type"]?.string ?? ""
            caption = content["caption"]?["text"]?.string ?? ""
            duration = nil
            miniArtwork = nil
        case "messageVoiceNote":
            origin = .voiceNote
            let voice = content["voice_note"]
            file = voice?["voice"]
            title = ""
            performer = ""
            fileName = ""
            mimeType = voice?["mime_type"]?.string ?? "audio/ogg"
            caption = content["caption"]?["text"]?.string ?? ""
            duration = Int(voice?["duration"]?.int ?? 0)
            miniArtwork = nil
        default:
            return nil
        }

        guard let file, let fileId = file["id"]?.int, let uniqueId = file["remote"]?["unique_id"]?.string,
              !uniqueId.isEmpty
        else { return nil }

        let local = file["local"]
        let path = local?["path"]?.string ?? ""

        self.messageId = messageId
        self.chatId = chatId
        self.date = message["date"]?.int ?? 0
        self.origin = origin
        self.fileId = Int(fileId)
        self.uniqueId = uniqueId
        self.title = Self.fullTitle(title, from: caption)
        self.performer = performer
        self.fileName = fileName
        self.mimeType = mimeType
        self.caption = caption
        let size = file["size"]?.int ?? 0
        self.size = size > 0 ? size : (file["expected_size"]?.int ?? 0)
        self.duration = (duration ?? 0) > 0 ? duration : nil
        self.localPath = path.isEmpty ? nil : path
        self.isDownloaded = local?["is_downloading_completed"]?.bool ?? false
        self.miniArtwork = miniArtwork
    }

    /// The bots that post these files write the name twice — into the audio tag and into the
    /// caption — and cut the tag at about 64 characters: 93 of the 168 audios in the real
    /// channel arrive with a title ending in "…" while the same message's caption still holds
    /// the whole name. Telegram would show the cut tag; a library should not, so the cut is
    /// replaced only where the caption is that same name with its ending put back. A caption
    /// that is cut as well keeps its own "…" — the list never claims a name it does not have.
    private static func fullTitle(_ title: String, from caption: String) -> String {
        guard title.hasSuffix(ellipsis) else { return title }
        let cut = String(title.dropLast())
        guard let whole = captionName(caption), whole.count > cut.count,
              folded(whole).hasPrefix(folded(cut))
        else { return title }
        return whole
    }

    private static let ellipsis = "…"

    /// The caption's own name line: `Tiêu đề:` over a mix, `Bài hát:` over a song. Only those
    /// keys count, so `Thời lượng: 1:11:37` — a value that carries a second colon — is never
    /// read as a title.
    private static func captionName(_ caption: String) -> String? {
        for line in caption.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon])
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, nameKeys.contains(where: { folded($0) == folded(key) }) else { continue }
            return value
        }
        return nil
    }

    private static let nameKeys = ["Tiêu đề", "Bài hát"]

    /// A bot writes names in caps and another in sentence case, and a caption's spacing is not
    /// the tag's, so the two are compared with case, diacritics, width and runs of space
    /// folded away. What is *shown* stays exactly as the caption wrote it.
    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The name the list shows. Tags first, then the caption the channel wrote,
    /// then the file name without its extension — the order Telegram's own audio
    /// row falls back through.
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if !caption.isEmpty { return caption.trimmingCharacters(in: .whitespacesAndNewlines) }
        return fileNameStem
    }

    /// Empty for a document with no caption: the row then shows the title alone.
    public var displayPerformer: String {
        performer
    }

    public var fileNameStem: String {
        (fileName as NSString).deletingPathExtension
    }

    public var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    /// A channel's MP3s arrive as documents with `application/octet-stream` more
    /// often than not, so the extension gets the last word.
    public var isAudio: Bool {
        switch origin {
        case .audio, .voiceNote:
            true
        case .document:
            mimeType.hasPrefix("audio/") || Self.audioExtensions.contains(fileExtension)
        }
    }

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "mp4", "aac", "flac", "ogg", "oga", "opus", "wav", "wma", "aiff", "ape", "alac"
    ]
}

/// A public channel the app indexes.
public struct TdChannel: Equatable, Sendable {
    public let chatId: Int64
    public let username: String
    public let title: String

    public init(chatId: Int64, username: String, title: String) {
        self.chatId = chatId
        self.username = username
        self.title = title
    }
}

/// One page of a channel's history.
public struct TdHistoryPage: Equatable, Sendable {
    public let messages: [TdJSON]
    public let tracks: [TdTrack]
    /// The lowest message id in the page — the cursor for the next one. TDLib
    /// sends pages in whatever order the server had them, so it is computed, not assumed.
    public let oldestMessageId: Int64?
    /// TDLib's own count of the messages it looked at; `nil` when it did not say.
    public let totalCount: Int?
    /// The walk is over when nothing older came back. A *short* page is not the
    /// end: TDLib returns the messages it has, so a channel with gaps answers
    /// with fewer than the limit and still has older posts.
    public let isLast: Bool

    init(messages: [TdJSON], totalCount: Int?) {
        self.messages = messages
        self.totalCount = totalCount
        self.tracks = messages.compactMap(TdTrack.init(message:)).filter(\.isAudio)
        self.oldestMessageId = messages.compactMap { $0["id"]?.int }.min()
        self.isLast = messages.isEmpty
    }

    public var trackCount: Int { tracks.count }
}
