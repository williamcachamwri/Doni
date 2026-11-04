import Foundation

/// One line of lyrics, with the stretch of the song it belongs to.
public struct LyricLine: Equatable, Sendable {
    /// When it is sung.
    public let start: TimeInterval
    /// When the next line starts — `.infinity` for the last one, because a final line is not
    /// finished until the song is.
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    public func contains(_ seconds: TimeInterval) -> Bool {
        seconds >= start && seconds < end
    }
}

/// What a lyrics lookup can come back with, in the order the app has to treat them.
public enum LyricText: Equatable, Sendable {
    /// Timed lines. What the view scrolls.
    case synced([LyricLine])
    /// Words without times: shown as a block, never highlighted.
    case plain(String)
    /// Nothing found, which is a state the screen says out loud rather than an empty scroll.
    case none

    public var lines: [LyricLine] {
        if case .synced(let lines) = self { return lines }
        return []
    }
}

/// The LRC format (`[mm:ss.xx]text`), which is what lrclib's `syncedLyrics` field carries and what
/// a `.lrc` file beside a song is made of.
///
/// Three things the format does that a naive line-by-line read gets wrong. A single line can carry
/// **several** timestamps — the same words sung again at the chorus — and each one is its own line.
/// A `[offset:]` tag is a millisecond shift applied to every timestamp in the file, and it is the
/// only tag that means something to a player. And the file is not necessarily in order, because
/// nothing in the format says it has to be.
public enum LRCParser {
    /// The lines, in singing order, each ending where the next begins.
    public static func lines(_ text: String) -> [LyricLine] {
        var marked: [(start: TimeInterval, text: String)] = []
        var offset = 0.0

        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }

            var stamps: [TimeInterval] = []
            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = String(line[line.index(after: line.startIndex)..<close])
                line = String(line[line.index(after: close)...])
                    .trimmingCharacters(in: .whitespaces)
                if let seconds = timestamp(tag) {
                    stamps.append(seconds)
                } else if let shift = offsetTag(tag) {
                    offset = shift
                }
                // Any other tag (`[by:]`, `[ti:]`, `[ar:]`) is metadata about the file, not words.
            }

            guard !stamps.isEmpty, !line.isEmpty else { continue }
            for stamp in stamps { marked.append((Swift.max(0, stamp + offset), line)) }
        }

        let sorted = marked.sorted { $0.start < $1.start }
        return sorted.enumerated().map { index, entry in
            LyricLine(start: entry.start,
                      end: index + 1 < sorted.count ? sorted[index + 1].start : .infinity,
                      text: entry.text)
        }
    }

    /// A whole `LyricText`: synced lines when the text has timestamps, plain when it has words and
    /// no times, nothing when it has neither.
    public static func parse(_ text: String?) -> LyricText {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .none
        }
        let lines = lines(text)
        if !lines.isEmpty { return .synced(lines) }
        return .plain(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `01:23`, `1:23.4`, `01:23.456` — seconds, with a fraction that may be hundredths or
    /// milliseconds. Returns nil for anything that is not a time, which is how a `[by:]` tag is
    /// told apart from a timestamp without a second pass.
    static func timestamp(_ tag: String) -> TimeInterval? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let minutes = Double(parts[0]), minutes >= 0,
              let seconds = Double(parts[1]), seconds >= 0, seconds < 60
        else { return nil }
        return minutes * 60 + seconds
    }

    /// `[offset:-120]` — the only tag a player has to obey, in milliseconds.
    static func offsetTag(_ tag: String) -> TimeInterval? {
        guard let colon = tag.firstIndex(of: ":") else { return nil }
        let name = tag[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard name == "offset",
              let value = Double(tag[tag.index(after: colon)...]
                  .trimmingCharacters(in: .whitespaces))
        else { return nil }
        return value / 1000
    }
}
