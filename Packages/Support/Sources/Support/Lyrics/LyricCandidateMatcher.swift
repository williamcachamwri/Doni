import Foundation

public struct LyricCandidate: Hashable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let durationSeconds: Int

    public init(title: String, artist: String, album: String,
                durationSeconds: Int) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
    }
}

public enum LyricCandidateMatcher {
    public static func searchQueries(for song: LyricSongMetadata) -> [String] {
        let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return [] }
        let cleanedTitle = removingParentheticalContent(from: title)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryArtist = song.artist
            .components(separatedBy: CharacterSet(charactersIn: ",，、/&"))
            .first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var queries: [String] = []
        if !primaryArtist.isEmpty {
            queries.append("\(title) \(primaryArtist)")
            if !cleanedTitle.isEmpty, cleanedTitle != title {
                queries.append("\(cleanedTitle) \(primaryArtist)")
            }
        }
        queries.append(title)
        if !cleanedTitle.isEmpty, cleanedTitle != title {
            queries.append(cleanedTitle)
        }
        return queries
    }

    public static func bestCandidate(in candidates: [LyricCandidate],
                                     for song: LyricSongMetadata) -> Int? {
        var best: (index: Int, score: Double)?
        for (index, candidate) in candidates.enumerated() {
            guard let score = confidence(candidate, for: song),
                  score >= 0.66 else { continue }
            if best == nil || score > best!.score {
                best = (index, score)
            }
        }
        return best?.index
    }

    static func isPlausible(_ candidate: LyricCandidate,
                            for song: LyricSongMetadata) -> Bool {
        confidence(candidate, for: song).map { $0 >= 0.66 } ?? false
    }

    private static func confidence(_ candidate: LyricCandidate,
                                   for song: LyricSongMetadata) -> Double? {
        let durationDelta = abs(candidate.durationSeconds - song.durationSeconds)
        guard durationDelta <= 8 else { return nil }
        let titleScore = titleSimilarity(candidate.title, song: song)
        guard titleScore >= 0.75 else { return nil }
        let artistScore = artistSimilarity(candidate.artist, song: song)
        if !song.artist.isEmpty, !candidate.artist.isEmpty, artistScore < 0.3 {
            return nil
        }
        let durationScore: Double
        switch durationDelta {
        case 0: durationScore = 1
        case ...2: durationScore = 0.85
        case ...5: durationScore = 0.7
        default: durationScore = 0.5
        }
        return titleScore * 0.45 + artistScore * 0.30 + durationScore * 0.15
            + albumSimilarity(candidate.album, song: song) * 0.10
    }

    private static func titleSimilarity(_ value: String,
                                        song: LyricSongMetadata) -> Double {
        let candidate = normalized(value)
        let title = normalized(song.title)
        guard !candidate.isEmpty, !title.isEmpty else { return 0 }
        if candidate == title { return 1 }
        let candidateCleaned = normalized(removingParentheticalContent(from: value))
        let titleCleaned = normalized(removingParentheticalContent(from: song.title))
        if !candidateCleaned.isEmpty, !titleCleaned.isEmpty,
           candidateCleaned == titleCleaned { return 0.95 }
        if title.contains(candidate) || candidate.contains(title)
            || (!titleCleaned.isEmpty
                && (titleCleaned.contains(candidate) || candidate.contains(titleCleaned))) {
            return 0.88
        }
        return 0.4
    }

    private static func artistSimilarity(_ value: String,
                                         song: LyricSongMetadata) -> Double {
        let candidateNames = artistNames(from: value)
        let songNames = artistNames(from: song.artist)
        if songNames.isEmpty { return 0.5 }
        if candidateNames.isEmpty { return 0.25 }
        if songNames.contains(where: { songName in
            candidateNames.contains(where: { candidateName in
                songName == candidateName || songName.contains(candidateName)
                    || candidateName.contains(songName)
            })
        }) { return 1 }
        return 0.15
    }

    private static func albumSimilarity(_ value: String,
                                        song: LyricSongMetadata) -> Double {
        let candidate = normalized(value)
        let album = normalized(song.album)
        guard !candidate.isEmpty, !album.isEmpty else { return 0.5 }
        if candidate == album { return 1 }
        return candidate.contains(album) || album.contains(candidate) ? 0.9 : 0.35
    }

    private static func artistNames(from source: String) -> [String] {
        source.components(separatedBy: CharacterSet(charactersIn: ",，、/&"))
            .map(normalized).filter { !$0.isEmpty }
    }

    private static func removingParentheticalContent(from source: String) -> String {
        source.replacingOccurrences(
            of: #"[\(（\[【][^\)）\]】]*[\)）\]】]"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func normalized(_ source: String) -> String {
        source.folding(options: [.caseInsensitive, .diacriticInsensitive,
                                 .widthInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }
}
