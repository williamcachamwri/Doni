import Foundation

/// Where a folded query actually sits inside the accented original.
///
/// `SearchTextFold.normalized` is the key both sides match on, but it collapses runs of whitespace, so
/// a range found in its output cannot be mapped back. This builds the same key one character at a time,
/// remembering which original character each emitted one came from.
public enum SearchHighlight {
    public static func ranges(of rawQuery: String, in text: String) -> [Range<String.Index>] {
        let query = Array(SearchTextFold.normalized(rawQuery))
        guard !query.isEmpty else { return [] }

        var key: [Character] = []
        var origins: [String.Index] = []
        var pendingSpace = false

        for index in text.indices {
            let character = text[index]
            if character.isWhitespace {
                pendingSpace = pendingSpace || !key.isEmpty
                continue
            }
            let folded = Array(SearchTextFold.normalized(String(character)))
            guard !folded.isEmpty else { continue }
            if pendingSpace {
                pendingSpace = false
                key.append(" ")
                origins.append(index)
            }
            for piece in folded {
                key.append(piece)
                origins.append(index)
            }
        }

        var ranges: [Range<String.Index>] = []
        var start = 0
        while start + query.count <= key.count {
            guard match(query, in: key, at: start) else {
                start += 1
                continue
            }
            let first = origins[start]
            let last = origins[start + query.count - 1]
            let range = first..<text.index(after: last)
            if let previous = ranges.last, previous.upperBound == first {
                ranges[ranges.count - 1] = previous.lowerBound..<range.upperBound
            } else {
                ranges.append(range)
            }
            start += query.count
        }
        return ranges
    }

    private static func match(_ query: [Character], in key: [Character], at offset: Int) -> Bool {
        for step in 0 ..< query.count where key[offset + step] != query[step] {
            return false
        }
        return true
    }

    /// The text split into the runs the caller styles: matched, then unmatched, alternating.
    public static func segments(of rawQuery: String, in text: String) -> [(text: String, isMatch: Bool)] {
        var segments: [(text: String, isMatch: Bool)] = []
        var cursor = text.startIndex
        for range in ranges(of: rawQuery, in: text) {
            if cursor < range.lowerBound {
                segments.append((String(text[cursor ..< range.lowerBound]), false))
            }
            segments.append((String(text[range.lowerBound ..< range.upperBound]), true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            segments.append((String(text[cursor...]), false))
        }
        return segments
    }
}
