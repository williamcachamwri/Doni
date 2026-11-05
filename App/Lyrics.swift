import CryptoKit
import DoniLyrics
import Foundation
import Support
import SwiftUI

/// The three things Doni decides about words for itself, apart from the fifty-odd typography and motion
/// numbers that belong to the screen's own settings.
@MainActor
final class LyricsPreferences: ObservableObject {
    static let shared = LyricsPreferences()

    /// Whether words may be fetched from lrclib at all; off, the screen shows only what is on the phone.
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

/// The words of the song that is playing. Four sources answer together — lrclib, NetEase, AMLL and QQ
/// Music — and the cache keeps the richest answer, misses included: a song with no lyric anywhere is
/// asked about once, not on every trip back to Now Playing.
@MainActor
final class Lyrics: ObservableObject {
    static let shared = Lyrics()

    @Published private(set) var lines: [LyricLine] = []
    /// Why there are no words when there are none, so a refused network and a song nobody has typed out
    /// look different on the screen.
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    /// Which song the published state belongs to; without it a lookup still in flight for a skipped song
    /// would answer for the one now playing.
    @Published private(set) var key: String?

    /// The settings the copied screen reads. One instance for the whole app: it is the user's
    /// typography, not a per-song opinion, and the screen animates against it.
    static let settings = AppSettings()

    private var task: Task<Void, Never>?
    private let prefs = LyricsPreferences.shared

    private init() {
        Self.settleCacheRevision()
    }

    /// A miss is only worth remembering while the pipeline that missed it is the one that would be asked
    /// again, so the revision travels with the question. Four of these songs' `N`s came from a build that
    /// knew lrclib alone and sent titles with `(320kbps)` still glued to them, and lrclib had those words
    /// the whole time. Only misses are dropped — found lyrics are never thrown away.
    nonisolated private static let revisionKey = "lyrics.revision"
    nonisolated private static let revision = 2

    private nonisolated static func settleCacheRevision() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: revisionKey) != revision else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where storedMarker(in: file) == "N" {
            try? FileManager.default.removeItem(at: file)
        }
        defaults.set(revision, forKey: revisionKey)
    }

    private nonisolated static func storedMarker(in file: URL) -> Character? {
        try? String(contentsOf: file, encoding: .utf8).first
    }

    /// The words for one song, from wherever they can come cheapest.
    func load(_ track: any Playable) {
        let song = Self.cacheKey(track)
        // Asked and answered already, or being asked: a redraw must not start a second lookup for the song
        // it is already showing.
        guard song != key else { return }
        key = song
        task?.cancel()
        if let stored = Self.read(song) {
            isLoading = false
            apply(stored, track: track)
            return
        }
        guard prefs.networkAllowed else {
            apply(.lrclib(.none), track: track)
            return
        }
        isLoading = true
        // Nothing on screen yet and no reason said: while the sites are thinking the screen shows
        // it is working, not that the song has no words.
        lines = []
        errorMessage = nil
        task = Task {
            let duration = Double(track.duration ?? 0)
            let outcome = await LyricsSources.fetch(
                metadata: Self.metadata(track),
                session: .shared
            )
            guard !Task.isCancelled, self.key == song else { return }
            switch outcome {
            case .failed:
                // None of the sources answered, which says nothing about whether the song has words:
                // nothing is written and the key is handed back, so a lost connection means the next
                // opening asks again.
                isLoading = false
                key = nil
                lines = []
                errorMessage = localized("Không kết nối được tới các nguồn lời")
            case .none:
                Self.write(.lrclib(.none), for: song)
                isLoading = false
                apply(.lrclib(.none), track: track)
            case .sources(let sources):
                let payload = LyricsResolver.resolve(sources, duration: duration)
                    ?? .lrclib(.none)
                Self.write(payload, for: song)
                isLoading = false
                apply(payload, track: track)
            }
        }
    }

    private func apply(_ payload: LyricsPayload, track: any Playable) {
        if case .lrclib(.none) = payload {
            lines = []
            errorMessage = localized(prefs.networkAllowed ? "Chưa tìm được lời cho bài này"
                                : "Việc tải lời đang tắt")
            return
        }
        if case .pureMusic = payload {
            lines = []
            errorMessage = localized("Bài này là nhạc không lời")
            return
        }
        if case .lrclib(.plain) = payload, !prefs.showPlain {
            lines = []
            errorMessage = localized("Chỉ có lời không khớp thời gian")
            return
        }
        lines = LyricsRenderer.lines(payload, duration: Double(track.duration ?? 0))
        errorMessage = lines.isEmpty ? localized("Lời không đọc được") : nil
    }

    // MARK: What goes out, and what stays

    /// The words kept under the song's own `file_unique_id` — the only id that means the same file in two
    /// databases. The row number does not survive a rebuild, and a cache keyed by it hands one song another
    /// song's words.
    private static func cacheKey(_ track: any Playable) -> String { track.uniqueId }

    private static func metadata(_ track: any Playable) -> LyricSongMetadata {
        LyricSongMetadata(title: track.displayTitle, artist: track.displayPerformer,
                          album: "", durationSeconds: Int(track.duration ?? 0))
    }

    /// The lyrics directory, made on the way in. Not `Caches`: these are words the site may stop serving,
    /// and iOS tidying the folder would lose them for good.
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

    private nonisolated static func read(_ key: String) -> LyricsPayload? {
        guard let text = try? String(contentsOf: file(key), encoding: .utf8) else { return nil }
        return LyricsCacheCodec.decode(text)
    }

    private nonisolated static func write(_ payload: LyricsPayload, for key: String) {
        try? LyricsCacheCodec.encode(payload).write(to: file(key), atomically: true,
                                                    encoding: .utf8)
    }
}
