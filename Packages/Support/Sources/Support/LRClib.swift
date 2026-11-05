import Foundation

/// What a lyrics lookup is asked with, and nothing more.
public struct LyricQuery: Equatable, Sendable {
    public let artist: String
    public let title: String
    /// Whole seconds, which is what lrclib matches on.
    public let duration: Int

    public init(artist: String, title: String, duration: Int) {
        self.artist = artist
        self.title = title
        self.duration = max(0, duration)
    }
}

/// lrclib's public JSON API (`https://lrclib.net`) — the source carrying the Western and Vietnamese
/// releases the Chinese catalogues do not. The least a lookup can work with goes: name, artist and
/// length; the accepted `file_size` is deliberately not sent, since it identifies the exact file rather
/// than the song. No album, no session, no device identifier.
///
/// Two shapes matter: `/api/get` answers **one object** and `/api/search` an **array**; reading only one
/// silently finds nothing. lrclib sends `""`, not `null`, for an absent field.
public enum LRClib {
    public static let base = URL(string: "https://lrclib.net")!

    /// The exact lookup: name, artist and length together.
    public static func getURL(_ query: LyricQuery) -> URL? {
        var parts = URLComponents(url: base.appending(path: "/api/get"),
                                  resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            .init(name: "track_name", value: query.title),
            .init(name: "artist_name", value: query.artist),
            .init(name: "duration", value: String(query.duration))
        ]
        return parts?.url
    }

    /// The loose one, for a song whose tags are spelled differently from the site's.
    public static func searchURL(_ query: LyricQuery) -> URL? {
        var parts = URLComponents(url: base.appending(path: "/api/search"),
                                  resolvingAgainstBaseURL: false)
        let words = [query.artist, query.title].filter { !$0.isEmpty }.joined(separator: " ")
        guard !words.isEmpty else { return nil }
        parts?.queryItems = [
            .init(name: "q", value: words),
            .init(name: "duration", value: String(query.duration))
        ]
        return parts?.url
    }

    /// One answer. Only the two lyric fields are read; the rest of lrclib's object is its own
    /// business and is deliberately not modelled, so a new field upstream cannot break a decode.
    public struct Entry: Decodable, Equatable {
        public let syncedLyrics: String?
        public let plainLyrics: String?

        public init(syncedLyrics: String?, plainLyrics: String?) {
            self.syncedLyrics = syncedLyrics
            self.plainLyrics = plainLyrics
        }
    }

    /// The answer, or `nil` when no request reached the site. A channel's caption is not the song's
    /// name: titles arrive carrying the upload's bitrate, e.g. `… & 2PILLZ (320kbps)`, which lrclib
    /// answers with nothing — so every title is asked twice, as the row spells it and with the quality
    /// noise taken out.
    public static func fetch(_ query: LyricQuery,
                             session: URLSession = .shared) async -> LyricText? {
        var reached = false
        for title in titles(for: query) {
            let probe = LyricQuery(artist: query.artist, title: title,
                                   duration: query.duration)
            // `/api/get` answers 400 for an empty artist, and a captionless channel post has none.
            let hasArtist = !probe.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasArtist, let exact = getURL(probe), let hits = await send(exact, session: session) {
                reached = true
                let found = text(of: hits)
                if found != .none { return found }
            }
            if let loose = searchURL(probe), let hits = await send(loose, session: session) {
                reached = true
                let found = text(of: hits)
                if found != .none { return found }
            }
        }
        return reached ? LyricText.none : nil
    }

    /// The spellings worth asking, in order: what the row says, then the same name with the
    /// upload's own noise — a bitrate, a codec, an extension — taken out of it.
    public static func titles(for query: LyricQuery) -> [String] {
        let raw = query.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        let cleaned = removingUploadNoise(from: raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != raw else { return [raw] }
        return [raw, cleaned]
    }

    /// A bracketed group only says how the file was encoded, and a trailing `.mp3` only says what
    /// the uploader called it. Neither is part of the song's name, and lrclib matches on the name.
    private static func removingUploadNoise(from title: String) -> String {
        var text = title
        text = text.replacingOccurrences(
            of: #"[\[(]\s*(?:\d+\s*k?bps|mp3|m4a|flac|aac|opus|hq|hd|4k|lossless|320|256|128)\s*[\])]"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"\.(?:mp3|m4a|flac|aac|opus)$"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"\s{2,}"#, with: " ", options: [.regularExpression]
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—,_.•"))
    }

    /// Both shapes, in one call: an array, or the single object `/api/get` answers with.
    public static func entries(_ data: Data) -> [Entry] {
        if let many = try? JSONDecoder().decode([Entry].self, from: data) { return many }
        if let one = try? JSONDecoder().decode(Entry.self, from: data) { return [one] }
        return []
    }

    /// `nil` means the site was not reached. A `404` is the opposite: an answer, and the answer is
    /// "not in here" — which is worth caching, while a refusal to connect is not.
    private static func send(_ url: URL, session: URLSession) async -> [Entry]? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Doni/1.0 (personal music player)",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return [] }
        guard (200..<300).contains(http.statusCode) else { return nil }
        return entries(data)
    }

    /// Synced first, plain second, nothing third — the order the user asked for, applied to every
    /// answer in turn so the first entry that actually has words wins.
    public static func text(of entries: [Entry]) -> LyricText {
        for entry in entries {
            if let synced = filled(entry.syncedLyrics), stamped(synced) { return .synced(synced) }
        }
        for entry in entries {
            if let plain = filled(entry.plainLyrics) { return .plain(plain) }
        }
        return .none
    }

    /// Whether the field actually carries `[mm:ss.xx]` stamps: lrclib labels a lyric "synced" then
    /// serves plain text under it, and treating that as timed words stacks every line on second zero.
    private static func stamped(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { $0.firstMatch(of: /^\s*\[\d{1,2}:\d\d/) != nil }
    }

    /// `""` is lrclib for "not here", and treating it as a lyric is how an empty scroll happens.
    private static func filled(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
}
