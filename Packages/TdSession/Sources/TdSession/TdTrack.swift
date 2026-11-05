import Foundation

/// One playable thing a channel message carries. A music channel posts the same song as `messageAudio`
/// (uploaded as audio, so it has tags) or `messageDocument` (a file, so only a name and a size), and both
/// share the dedupe key `file.remote.unique_id`: TDLib's `file:id:int32` (`td_api.tl:326`) is
/// per-database, while MTProto's `file_unique_id` repeats across messages, channels and re-uploads.
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
    /// TDLib's `minithumbnail` for the cover tag: a few hundred bytes of JPEG the message itself
    /// carries, so the list shows real artwork without asking for a file. `nil` for a bare post.
    public let miniArtwork: Data?
    /// The cover worth fetching, picked from TDLib's three — `album_cover_thumbnail` and the two
    /// `external_album_covers` (`td_api.tl:583`).
    ///
    /// One that already reports bytes wins over a bigger one that reports none: the external covers are
    /// *generated* files, located out of the title and performer (`FileManager.cpp:4361`,
    /// `AudiosManager.cpp:53-67`), answering `size` and `expected_size` as 0 until the server has made
    /// the bytes — measured on 168 of 168 audios, while 112 carry a 320×240 thumbnail of 6.6-31 KB.
    public let coverFileId: Int?
    /// The same cover's MTProto identity, the half worth caching. `file:id:int32` (`td_api.tl:326`)
    /// counts rows in *this* database, so it is only good while the database is; `remote:unique_id`
    /// (`:318`) is the file's name on Telegram's side, the same in every database and re-upload. The
    /// copy on the phone outlives the numbers, so it is filed under the identity — keyed on the row
    /// number, a re-index hands one song another song's cover.
    public let coverUniqueId: String?

    /// A post's cover: TDLib's row number for the download, MTProto's identity for what is kept.
    private typealias Cover = (fileId: Int, uniqueId: String?)

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
        let cover: Cover?

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
            // TDLib serialises `bytes` as base64; this is the only artwork that comes with the
            // message rather than as a file to fetch (`td_api.tl:583`,
            // `audio.album_cover_minithumbnail`). A document's minithumbnail is a drawn file icon.
            let encodedArtwork = audio?["album_cover_minithumbnail"]?["data"]?.string
            miniArtwork = encodedArtwork.flatMap { Data(base64Encoded: $0) }
            cover = Self.bestCover(audio)
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
            cover = nil
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
            cover = nil
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
        // A document post has no performer field of its own (`td_api.tl:594`), and a bot naming the
        // singer at all names it in the caption; the tag still comes first where both exist.
        self.performer = performer.isEmpty
            ? (Self.captionValue(caption, keys: Self.artistKeys) ?? "")
            : performer
        self.fileName = fileName
        self.mimeType = mimeType
        self.caption = caption
        let size = file["size"]?.int ?? 0
        self.size = size > 0 ? size : (file["expected_size"]?.int ?? 0)
        self.duration = (duration ?? 0) > 0 ? duration : nil
        self.localPath = path.isEmpty ? nil : path
        self.isDownloaded = local?["is_downloading_completed"]?.bool ?? false
        self.miniArtwork = miniArtwork
        self.coverFileId = cover?.fileId
        self.coverUniqueId = cover?.uniqueId
    }

    /// The cover to ask TDLib for, out of every thumbnail the post carries, with its identity. Ones with
    /// bytes come first and, among them, the widest: a 320 px `album_cover_thumbnail` is a download that
    /// can start now, where a 600 px generated cover that never starts is worth less than nothing.
    private static func bestCover(_ audio: TdJSON?) -> Cover? {
        var candidates: [TdJSON] = []
        if let thumbnail = audio?["album_cover_thumbnail"] { candidates.append(thumbnail) }
        candidates.append(contentsOf: audio?["external_album_covers"]?.array ?? [])
        let sized = candidates.filter { Self.bytes(of: $0) > 0 }
        return Self.widest(sized) ?? Self.widest(candidates)
    }

    /// Bytes TDLib will promise about a thumbnail now: `size` once it has seen the file,
    /// `expected_size` while it has not; a generated cover promises neither.
    private static func bytes(of thumbnail: TdJSON) -> Int64 {
        guard let file = thumbnail["file"] else { return 0 }
        return max(file["size"]?.int ?? 0, file["expected_size"]?.int ?? 0)
    }

    /// The widest of TDLib's `thumbnail` objects (`td_api.tl:393`), the one worth a download: a 54 pt
    /// tile at @3x wants 162 pixels, and 100×100 is not enough. The identity comes from the same `file`
    /// object as the number, so the two are never a pair from different thumbnails; a
    /// `fileRemoteUnknown` remote has none and the caller has only the number.
    private static func widest(_ thumbnails: [TdJSON]) -> Cover? {
        let ranked = thumbnails.compactMap { entry -> (width: Int, cover: Cover)? in
            guard let width = entry["width"]?.int, let file = entry["file"],
                  let id = file["id"]?.int else { return nil }
            let unique = file["remote"]?["unique_id"]?.string
            return (Int(width), (Int(id), unique.flatMap { $0.isEmpty ? nil : $0 }))
        }
        return ranked.max { $0.width < $1.width }?.cover
    }

    /// These bots write the name twice — into the audio tag, cut at about 64 characters, and into the
    /// caption: 93 of the 168 audios in the real channel arrive ending in "…" while the caption holds
    /// the whole name. The cut is replaced only where the caption is that name with its ending back.
    private static func fullTitle(_ title: String, from caption: String) -> String {
        guard title.hasSuffix(ellipsis) else { return title }
        let cut = String(title.dropLast())
        guard let whole = captionName(caption), whole.count > cut.count,
              folded(whole).hasPrefix(folded(cut))
        else { return title }
        return whole
    }

    private static let ellipsis = "…"

    /// The caption's own name line: `Tiêu đề:` over a mix, `Bài hát:` over a song. Only those keys
    /// count, so `Thời lượng: 1:11:37` is never read as a title.
    private static func captionName(_ caption: String) -> String? {
        captionValue(caption, keys: nameKeys)
    }

    private static let nameKeys = ["Tiêu đề", "Bài hát"]

    /// Who sang it, out of the caption. `Thể hiện:` is the one these channels write — 59 of the 168
    /// measured posts — the rest are keys the same bots use in English or copy off a streaming service.
    /// A row with no singer named stays unnamed rather than being called by the app's own name.
    private static let artistKeys = ["Thể hiện", "Ca sĩ", "Trình bày", "Singer", "Artist", "Vocal"]

    /// The value of the first caption line whose key is one of `keys`, compared with case, diacritics
    /// and spacing folded away, and nothing at all when no line matches.
    private static func captionValue(_ caption: String, keys: [String]) -> String? {
        for line in caption.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon])
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, keys.contains(where: { folded($0) == folded(key) }) else { continue }
            return value
        }
        return nil
    }

    /// Caps against sentence case and a caption's spacing against the tag's: compared with case,
    /// diacritics, width and space runs folded. What is *shown* stays as the caption wrote it.
    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The name the list shows: tags, then the caption's name line, then the caption, then the file
    /// name without its extension — Telegram's own fallback order. The name line comes before the whole
    /// caption because a caption with keys is a form, not a name.
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if let named = Self.captionName(caption) { return named }
        if !caption.isEmpty { return caption.trimmingCharacters(in: .whitespacesAndNewlines) }
        return fileNameStem
    }

    /// Who sang it; empty when neither the tag nor the caption named anyone.
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

/// A chat the app reads songs out of. The name is the app's, not Telegram's: the walk is one request
/// whatever the chat is, so a channel, a group, a person and a bot are the same kind of source.
public struct TdChannel: Equatable, Sendable {
    /// What the chat is, which is what the picker says it is.
    public enum Kind: String, Equatable, Sendable {
        case channel, group, user, bot
    }

    public let chatId: Int64
    public let username: String
    public let title: String
    public let kind: Kind
    /// The chat's own picture, or nil when it has never set one. Every request answering a `chat`
    /// carries it — `searchPublicChat`, `getChat`, the chat list — so no second round trip is needed.
    public let photo: TdChatPhoto?

    /// A handle only comes from a search by handle; the chat list has none to give
    /// (`td_api.tl:4080`), and an id is enough to walk a chat.
    public init(chatId: Int64, username: String, title: String, kind: Kind = .channel,
                photo: TdChatPhoto? = nil) {
        self.chatId = chatId
        self.username = username
        self.title = title
        self.kind = kind
        self.photo = photo
    }
}

/// A chat's own picture, as TDLib describes it. `chat.photo` (`td_api.tl:4080`) is a `chatPhotoInfo`
/// (`:784`) with two still variants: `small` at 160×160 and `big` at 640×640 (`:779`, `:780`), and the
/// smaller is asked for — five times the pixels a 30 pt mark needs, a fraction of the other's bytes.
///
/// `fileId` is TDLib's row number (`:326`), what a download is asked for by; `uniqueId` is MTProto's
/// identity for the same bytes, what the kept copy is named after — a picture filed under a row number
/// one day belongs to a different chat.
public struct TdChatPhoto: Equatable, Sendable {
    public let fileId: Int
    public let uniqueId: String?

    public init(fileId: Int, uniqueId: String?) {
        self.fileId = fileId
        self.uniqueId = uniqueId
    }

    /// The `photo` of a `chat`, or nil for a chat with no picture. TDLib answers an empty
    /// `chatPhotoInfo` for those and a `file` of id 0 for a variant it lacks, so the number decides
    /// rather than the object's presence. The identity comes from the same variant as the number, so
    /// one file's id is never paired with another's `unique_id`.
    public init?(chat: TdJSON) {
        guard let photo = chat["photo"] else { return nil }
        for variant in ["small", "big"] {
            guard let file = photo[variant], let number = file["id"]?.int, number != 0 else {
                continue
            }
            let remote = file["remote"]?["unique_id"]?.string
            fileId = Int(number)
            uniqueId = (remote?.isEmpty ?? true) ? nil : remote
            return
        }
        return nil
    }
}

/// One page of a channel's history.
public struct TdHistoryPage: Equatable, Sendable {
    public let messages: [TdJSON]
    public let tracks: [TdTrack]
    /// The lowest message id in the page — the cursor for the next one. TDLib
    /// sends pages in whatever order the server had them, so it is computed, not assumed.
    public let oldestMessageId: Int64?
    /// TDLib's count of the messages it looked at; `nil` when it did not say.
    public let totalCount: Int?
    /// The walk is over when nothing older came back. A *short* page is not the end: TDLib returns the
    /// messages it has, so a channel with gaps answers under the limit and still has older posts.
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
