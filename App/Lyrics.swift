import CryptoKit
import DoniLyrics
import Foundation
import Support
import SwiftUI

/// A lookup that never got an answer, as distinct from one that answered "no lyrics".
private enum LyricsFetchFailure: Error {
    case status
}

/// The three things Doni decides about words for itself, as opposed to the fifty-odd
/// typography and motion numbers that belong to the screen and live in its own settings.
@MainActor
final class LyricsPreferences: ObservableObject {
    static let shared = LyricsPreferences()

    /// Whether words may be fetched from lrclib at all. Off, the screen shows only what is already
    /// on the phone — a `.lrc` beside the song, or nothing.
    @Published var networkAllowed = true { didSet { write("network", networkAllowed) } }
    /// Seconds added to every stamp, for a file whose lyrics were timed against another mastering.
    @Published var offset = 0.0 { didSet { write("offset", offset) } }
    /// Words with no timestamps: spread across the song, or left out until something timed is found.
    @Published var showPlain = true { didSet { write("plain", showPlain) } }

    private let defaults = UserDefaults.standard

    private init() {
        if defaults.object(forKey: "lyrics.network") != nil {
            networkAllowed = defaults.bool(forKey: "lyrics.network")
            offset = defaults.double(forKey: "lyrics.offset")
            showPlain = defaults.bool(forKey: "lyrics.plain")
        }
    }

    private func write(_ key: String, _ value: Any) {
        defaults.set(value, forKey: "lyrics.\(key)")
    }
}

/// The words of the song that is playing.
///
/// Three sources, in order of what they cost the user: a file beside the song, the phone's own
/// cache, and only then lrclib. The cache keeps its misses too — a song with no lyric anywhere is
/// asked about once, not on every trip back to the Now Playing screen, because the site rate
/// limits a client that forgets.
///
/// What it hands the screen is the reference's own line model, parsed by the reference's own LRC
/// parser. Which line is being sung is not this object's business: the screen reads the player's
/// clock and works that out for itself.
@MainActor
final class Lyrics: ObservableObject {
    static let shared = Lyrics()

    @Published private(set) var lines: [LyricLine] = []
    /// Why there are no words, when there are none — the screen shows this instead of a blank
    /// column, so a refused network and a song nobody has ever typed out look different.
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    /// Which song the published state belongs to. Without it a lookup still in flight for the song
    /// the user skipped would answer for the one now playing.
    @Published private(set) var key: String?

    /// The settings the copied screen reads. One instance for the whole app: it is the user's
    /// typography, not a per-song opinion, and the screen animates against it.
    static let settings = AppSettings()

    private var task: Task<Void, Never>?
    private let prefs = LyricsPreferences.shared

    private init() {}

    /// The words for one song, from wherever they can come cheapest.
    func load(_ track: any Playable) {
        let song = Self.cacheKey(track)
        // Asked and answered already, or being asked right now: a row that redraws must not start a
        // second lookup for the song it is already showing.
        guard song != key else { return }
        key = song
        task?.cancel()
        if let stored = Self.read(song) {
            isLoading = false
            apply(stored, track: track)
            return
        }
        guard prefs.networkAllowed else {
            apply(.none, track: track)
            return
        }
        isLoading = true
        // Nothing on screen yet and no reason said: while the site is thinking the screen shows
        // it is working, not that the song has no words.
        lines = []
        errorMessage = nil
        task = Task {
            guard let found = await Self.fetch(query: Self.query(track)) else {
                // The site was not reached. That says nothing about whether this song has words,
                // so nothing is written down and the song's key is handed back: opening it again
                // asks the question again, which is what a lost connection has to mean. A one-off
                // rate limit used to be filed as "no lyrics" and read back forever.
                guard !Task.isCancelled, self.key == song else { return }
                isLoading = false
                key = nil
                lines = []
                errorMessage = localized("Không kết nối được tới lrclib")
                return
            }
            // The song moved on, or the screen went away, while the site was thinking.
            guard !Task.isCancelled, self.key == song else { return }
            Self.write(found, for: song)
            isLoading = false
            apply(found, track: track)
        }
    }

    private func apply(_ found: LyricText, track: any Playable) {
        switch found {
        case .none:
            lines = []
            errorMessage = localized(prefs.networkAllowed ? "Chưa tìm được lời cho bài này"
                                : "Việc tải lời đang tắt")
        case .plain(let text):
            guard prefs.showPlain else {
                lines = []
                errorMessage = localized("Chỉ có lời không khớp thời gian")
                return
            }
            lines = Self.spread(text, over: Double(track.duration ?? 0))
            errorMessage = nil
        case .synced:
            lines = Self.parse(found)
            errorMessage = lines.isEmpty ? localized("Lời không đọc được") : nil
        }
    }

    // MARK: Lines

    /// The reference's parser, on the LRC text that was cached or found.
    private nonisolated static func parse(_ found: LyricText) -> [LyricLine] {
        guard let text = lrc(found) else { return [] }
        return LyricParser.parseLRC(text)
    }

    /// Words that arrived without a single timestamp.
    ///
    /// The screen only knows how to follow a line that has a time, so an untimed block gets the
    /// one thing that can be said about it honestly: the lines are in order, and the song is the
    /// length it is. Each line therefore owns an equal slice of it, which is the reference's own
    /// "line synchronized" kind rather than a claim that anyone timed them.
    private nonisolated static func spread(_ text: String, over duration: TimeInterval) -> [LyricLine] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty, duration > 0 else { return [] }
        let slice = duration / Double(lines.count)
        return lines.enumerated().map { offset, line in
            LyricLine(
                time: Double(offset) * slice,
                duration: slice,
                timingKind: .lineSynchronized,
                text: line
            )
        }
    }

    // MARK: What goes out, and what stays

    /// The name the words are kept under. The song's own `file_unique_id`, which is the only id that
    /// means the same file in two databases — the row number does not survive a rebuild, and a cache
    /// keyed by it hands one song another song's words.
    private static func cacheKey(_ track: any Playable) -> String { track.uniqueId }

    private static func query(_ track: any Playable) -> LyricQuery {
        LyricQuery(artist: track.displayPerformer, title: track.displayTitle,
                   duration: Int(track.duration ?? 0))
    }

    /// The lyrics directory, made on the way in. Not `Caches`: these are words the site may stop
    /// serving, and a song the user has to look up again because iOS tidied a folder is the same
    /// complaint they already have about artwork.
    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Doni/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private nonisolated static func file(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent("\(name).lrc")
    }

    /// `S` for synced, `P` for plain, `N` for "asked and there was nothing" — the miss is worth
    /// keeping, because asking again is a network call that will miss again.
    private nonisolated static func read(_ key: String) -> LyricText? {
        guard let text = try? String(contentsOf: file(key), encoding: .utf8) else { return nil }
        switch text.first {
        case "S": return .synced(String(text.dropFirst()))
        case "P": return .plain(String(text.dropFirst()))
        case "N": return LyricText.none
        default: return nil
        }
    }

    private nonisolated static func write(_ found: LyricText, for key: String) {
        let body: String
        switch found {
        case .synced: body = "S" + (lrc(found) ?? "")
        case .plain: body = "P" + (lrc(found) ?? "")
        case .none: body = "N"
        }
        try? body.write(to: file(key), atomically: true, encoding: .utf8)
    }

    /// The LRC text behind a result. Synced words are stored as the stamps they arrived with, so
    /// reading them back is a parse and not a reconstruction.
    private nonisolated static func lrc(_ found: LyricText) -> String? {
        switch found {
        case .synced(let text): return text
        case .plain(let text): return text
        case .none: return nil
        }
    }

    /// The answer, or `nil` when the question never reached the site.
    ///
    /// `/api/get` first, because it matches on the length as well and a wrong-length match is a
    /// different recording; `/api/search` when the exact one finds nothing, because a bot that posts
    /// these files spells the title differently from the site.
    private nonisolated static func fetch(query: LyricQuery) async -> LyricText? {
        if let exact = LRClib.getURL(query), let hits = try? await send(exact), !hits.isEmpty {
            return LRClib.text(of: hits)
        }
        guard let loose = LRClib.searchURL(query) else { return LyricText.none }
        guard let hits = try? await send(loose) else { return nil }
        return LRClib.text(of: hits)
    }

    /// One request, decoded whichever shape the endpoint answered with. A `nil` here is the network
    /// refusing, and an empty array is the site answering "not in here" — the second is worth
    /// caching and the first is not.
    private nonisolated static func send(_ url: URL) async throws -> [LRClib.Entry] {
        var request = URLRequest(url: url, timeoutInterval: 12)
        // The site asks for something that identifies the client, and a generic one is how a
        // personal app gets rate limited into silence.
        request.setValue("Doni/1.0 (personal music player)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        // lrclib answers a rate limit with a body and a 429, and a body that is not a lyric decodes
        // to the same empty list as "not in here" — so the status is the only thing that separates
        // an answer from a refusal, and the refusal must not be filed as an answer.
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LyricsFetchFailure.status
        }
        return LRClib.entries(data)
    }
}
