import CryptoKit
import Foundation
import Support
import SwiftUI

/// How the lyrics screen behaves, and how much of the phone it is allowed to use.
///
/// Held in `UserDefaults` rather than in the library: these are opinions about reading words on a
/// screen, not data about songs, and they have to be readable by the view without a database
/// round trip while the lines are already moving.
@MainActor
final class LyricsPreferences: ObservableObject {
    static let shared = LyricsPreferences()

    /// Whether words may be fetched from lrclib at all. Off, the screen shows only what is already
    /// on the phone — a `.lrc` beside the song, or nothing.
    @Published var networkAllowed = true { didSet { write("network", networkAllowed) } }
    /// The size every line is drawn at, multiplied against the reference's own metrics.
    @Published var scale = 1.0 { didSet { write("scale", scale) } }
    /// Inactive lines go soft rather than small, which is what keeps the next line readable.
    @Published var blurInactive = true { didSet { write("blur", blurInactive) } }
    /// The centre column, or the leading edge — Apple Music centres, MeloX's floating style does not.
    @Published var centred = true { didSet { write("centred", centred) } }
    /// Tapping a line takes the song there.
    @Published var tapToSeek = true { didSet { write("seek", tapToSeek) } }
    /// Whether the scroll follows the song, or stays where the finger left it.
    @Published var autoFollow = true { didSet { write("follow", autoFollow) } }
    /// Seconds added to every stamp, for a file whose lyrics were timed against another mastering.
    @Published var offset = 0.0 { didSet { write("offset", offset) } }
    /// Words with no timestamps: shown as a block, or left out until something timed is found.
    @Published var showPlain = true { didSet { write("plain", showPlain) } }

    private let defaults = UserDefaults.standard

    private init() {
        // Read back what was written, because the first frame of the lyrics screen should already
        // be in the user's own settings rather than the default ones for a moment.
        if defaults.object(forKey: "lyrics.network") != nil {
            networkAllowed = defaults.bool(forKey: "lyrics.network")
            scale = defaults.double(forKey: "lyrics.scale")
            blurInactive = defaults.bool(forKey: "lyrics.blur")
            centred = defaults.bool(forKey: "lyrics.centred")
            tapToSeek = defaults.bool(forKey: "lyrics.seek")
            autoFollow = defaults.bool(forKey: "lyrics.follow")
            offset = defaults.double(forKey: "lyrics.offset")
            showPlain = defaults.bool(forKey: "lyrics.plain")
        }
    }

    private func write(_ key: String, _ value: Any) {
        defaults.set(value, forKey: "lyrics.\(key)")
    }
}

/// The words of the song that is playing, and which of them is being sung.
///
/// Three sources, in order of what they cost the user: a file beside the song, the phone's own
/// cache, and only then lrclib. The cache keeps its misses too — a song with no lyric anywhere is
/// asked about once, not on every trip back to the Now Playing screen, because the site rate
/// limits a client that forgets.
@MainActor
final class Lyrics: ObservableObject {
    static let shared = Lyrics()

    @Published private(set) var text: LyricText = .none
    /// The line under the playhead, and how far into it the song has got — the two numbers the
    /// view animates from.
    @Published private(set) var index: Int?
    @Published private(set) var progress = 0.0
    @Published private(set) var isLoading = false
    /// Which song the published state belongs to. Without it a lookup still in flight for the song
    /// the user skipped would answer for the one now playing.
    @Published private(set) var key: String?

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
            apply(stored)
            return
        }
        guard prefs.networkAllowed else {
            apply(.none)
            return
        }
        isLoading = true
        apply(.none)
        task = Task {
            let found = await Self.fetch(query: Self.query(track))
            // The song moved on, or the screen went away, while the site was thinking.
            guard !Task.isCancelled, self.key == song else { return }
            Self.write(found, for: song)
            isLoading = false
            apply(found)
        }
    }

    /// Where the playhead is. Called from the view's own clock rather than from a timer of its own,
    /// because the player already publishes the position four times a second and a second clock
    /// would only disagree with the first.
    func update(seconds: TimeInterval) {
        let shifted = seconds - prefs.offset
        switch text {
        case .none, .plain:
            index = nil
            progress = 0
        case .synced(let lines):
            guard let found = lines.firstIndex(where: { $0.contains(shifted) }) else {
                // Before the first line, and after the last one, the screen keeps showing something:
                // the song has not stopped, only the words have.
                index = shifted < lines.first?.start ?? 0 ? nil : lines.count - 1
                progress = 0
                return
            }
            index = found
            let line = lines[found]
            let span = line.end - line.start
            progress = span > 0 ? min(max((shifted - line.start) / span, 0), 1) : 1
        }
    }

    private func apply(_ found: LyricText) {
        // An untimed block is only shown if the user asked for it; otherwise the screen says it is
        // looking for something better rather than pretending a wall of text is a lyric.
        if case .plain = found, !prefs.showPlain {
            text = .none
        } else {
            text = found
        }
        index = nil
        progress = 0
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
        case "S": return LRCParser.parse(String(text.dropFirst()))
        case "P": return LRCParser.parse(String(text.dropFirst()))
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

    private nonisolated static func lrc(_ found: LyricText) -> String? {
        switch found {
        case .synced(let lines):
            return lines.map { String(format: "[%02d:%05.2f]%@",
                                      Int($0.start) / 60, $0.start - (Double(Int($0.start) / 60) * 60),
                                      $0.text) }.joined(separator: "\n")
        case .plain(let text): return text
        case .none: return nil
        }
    }

    /// `/api/get` first, because it matches on the length as well and a wrong-length match is a
    /// different recording; `/api/search` when the exact one finds nothing, because a bot that posts
    /// these files spells the title differently from the site.
    private nonisolated static func fetch(query: LyricQuery) async -> LyricText {
        if let exact = LRClib.getURL(query), let hits = try? await send(exact), !hits.isEmpty {
            return LRClib.text(of: hits)
        }
        guard let loose = LRClib.searchURL(query), let hits = try? await send(loose) else {
            return .none
        }
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
        let (data, _) = try await URLSession.shared.data(for: request)
        return LRClib.entries(data)
    }
}
