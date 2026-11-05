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
    /// The cover worth fetching, picked from TDLib's three of them — `album_cover_thumbnail` and
    /// the two `external_album_covers` (`td_api.tl:583`).
    ///
    /// A thumbnail that already reports bytes wins over a bigger one that reports none, because
    /// the external covers are *generated* files: TDLib builds their location out of the title and
    /// the performer (`FileManager.cpp:4361`, `AudiosManager.cpp:53-67`) and answers `size` and
    /// `expected_size` as 0 until the server has made the bytes. In the measured channel they are
    /// on 168 of 168 audios with no size on any of them, while 112 audios carry a 320×240 or
    /// 320×180 `album_cover_thumbnail` of 6.6-31 KB — which this app never used to read at all.
    public let coverFileId: Int?
    /// The same cover's MTProto identity, which is the half worth caching.
    ///
    /// `file:id:int32` (`td_api.tl:326`) counts rows in *this* database, so it is only good while
    /// the database is; `remote:unique_id` (`:318`) is the file's name on Telegram's side and is the
    /// same in every database, channel and re-upload. The picture kept on the phone outlives the
    /// numbers, so it has to be filed under the identity rather than the row number — keyed on the
    /// number, a re-index hands one song another song's cover.
    ///
    /// `nil` only for a row written before this was recorded; the covers in the measured channel all
    /// carry one, on both the 112 `album_cover_thumbnail` and the 336 `external_album_covers`.
    public let coverUniqueId: String?

    /// The cover a post carries: TDLib's row number for the download, and MTProto's identity for
    /// everything worth keeping.
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
            // TDLib serialises `bytes` as base64; this is the only artwork that comes
            // with the message rather than as a file that has to be fetched
            // (`td_api.tl:583`, `audio.album_cover_minithumbnail`). A document's own
            // minithumbnail is a drawn file icon, so it is not artwork and stays unread.
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
        // A document post has no performer field of its own (`td_api.tl:594`), and the bot that names
        // the singer at all names it in the caption. The tag still comes first where both exist: the
        // caption is prose a bot typed, the tag is what the file was made with.
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

    /// The cover to ask TDLib for, out of every thumbnail the post carries, with the identity of the
    /// file it picked.
    ///
    /// Ones with bytes are considered first and, among them, the widest: a 320 px `album_cover_thumbnail`
    /// is a download that can start now, and a 600 px generated cover that never starts is worth less
    /// than nothing to a row. Only when the post has no sized cover at all does the generated one get
    /// its turn, which is the whole of what a track posted without a proper tag has to offer.
    private static func bestCover(_ audio: TdJSON?) -> Cover? {
        var candidates: [TdJSON] = []
        if let thumbnail = audio?["album_cover_thumbnail"] { candidates.append(thumbnail) }
        candidates.append(contentsOf: audio?["external_album_covers"]?.array ?? [])
        let sized = candidates.filter { Self.bytes(of: $0) > 0 }
        return Self.widest(sized) ?? Self.widest(candidates)
    }

    /// Bytes TDLib is willing to promise about a thumbnail right now. `size` once it has seen the
    /// file, `expected_size` while it has not — and a generated cover promises neither.
    private static func bytes(of thumbnail: TdJSON) -> Int64 {
        guard let file = thumbnail["file"] else { return 0 }
        return max(file["size"]?.int ?? 0, file["expected_size"]?.int ?? 0)
    }

    /// The widest of TDLib's `thumbnail` objects (`td_api.tl:393`), which is the one worth a
    /// download: a 54 pt tile at @3x wants 162 pixels, and 100×100 is not enough.
    ///
    /// The remote identity comes from the same `file` object as the number, so the two can never be
    /// a pair from different thumbnails. A `fileRemoteUnknown` remote — what TDLib answers before it
    /// has looked the file up — has no identity, and the caller then has only the number to work with.
    private static func widest(_ thumbnails: [TdJSON]) -> Cover? {
        let ranked = thumbnails.compactMap { entry -> (width: Int, cover: Cover)? in
            guard let width = entry["width"]?.int, let file = entry["file"],
                  let id = file["id"]?.int else { return nil }
            let unique = file["remote"]?["unique_id"]?.string
            return (Int(width), (Int(id), unique.flatMap { $0.isEmpty ? nil : $0 }))
        }
        return ranked.max { $0.width < $1.width }?.cover
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
        captionValue(caption, keys: nameKeys)
    }

    private static let nameKeys = ["Tiêu đề", "Bài hát"]

    /// Who sang it, out of the caption. `Thể hiện:` is the one these channels write — 59 of the 168
    /// measured posts — and the others are the keys the same bots use when they post in English or
    /// copy a description off a streaming service.
    ///
    /// A row with no singer named stays unnamed rather than being called by the app's own name; the
    /// screens that need a second line decide what to say when there is nothing to say.
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

    /// A bot writes names in caps and another in sentence case, and a caption's spacing is not
    /// the tag's, so the two are compared with case, diacritics, width and runs of space
    /// folded away. What is *shown* stays exactly as the caption wrote it.
    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The name the list shows. Tags first, then the caption's own name line, then the caption as
    /// written, then the file name without its extension — the order Telegram's own audio row falls
    /// back through.
    ///
    /// The name line comes before the whole caption because a caption that has keys is not a name:
    /// `Tiêu đề: …\nThể hiện: …\nKênh: …` is a form, and showing it as a title puts four lines of a
    /// bot's bookkeeping on the row where a song's name should be.
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if let named = Self.captionName(caption) { return named }
        if !caption.isEmpty { return caption.trimmingCharacters(in: .whitespacesAndNewlines) }
        return fileNameStem
    }

    /// Who sang it. Empty when neither the file's tag nor the caption named anyone, and the row then
    /// shows the title alone.
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

/// A chat the app reads songs out of.
///
/// The name is the app's, not Telegram's: the walk is one request whatever the chat is, so a
/// channel, a group, a person and a bot are all the same kind of source here, and only the label
/// the picker puts on the row differs.
public struct TdChannel: Equatable, Sendable {
    /// What the chat is, which is what the picker says it is.
    public enum Kind: String, Equatable, Sendable {
        case channel, group, user, bot
    }

    public let chatId: Int64
    public let username: String
    public let title: String
    public let kind: Kind
    /// The chat's own picture, or nil when it has never set one. Every request that answers a `chat`
    /// carries it — `searchPublicChat`, `getChat`, the chat list — so a row picked out of one of them
    /// knows its avatar without a second round trip.
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

/// A chat's own picture, as TDLib describes it.
///
/// `chat.photo` (`td_api.tl:4080`) is a `chatPhotoInfo` (`:784`) with two still variants: `small` at
/// 160×160 and `big` at 640×640 (`:779`, `:780`). The smaller is what Telegram's own list avatars are
/// drawn from and is the one asked for — it is five times the pixels a 30 pt mark needs and a
/// fraction of the bytes of the other.
///
/// `fileId` is TDLib's row number in its own database (`:326`), which is what a download is asked for
/// by; `uniqueId` is MTProto's identity for the same bytes and is what the copy kept on the phone is
/// named after, because a picture filed under a row number is a picture that one day belongs to a
/// different chat.
public struct TdChatPhoto: Equatable, Sendable {
    public let fileId: Int
    public let uniqueId: String?

    public init(fileId: Int, uniqueId: String?) {
        self.fileId = fileId
        self.uniqueId = uniqueId
    }

    /// The `photo` of a `chat`, or nil for a chat that has no picture. TDLib answers an empty
    /// `chatPhotoInfo` for those and a `file` of id 0 for a variant it does not have, so the number
    /// is what decides rather than the presence of the object.
    ///
    /// The identity is read out of the same variant as the number: pairing one file's id with
    /// another's `unique_id` would name the bytes being downloaded after a picture that was never
    /// asked for.
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
