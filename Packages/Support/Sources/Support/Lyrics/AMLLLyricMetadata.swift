import Foundation

struct AMLLLyricMetadata {
    let ncmMusicID: Int?
    let musicName: String?
    let artists: String?

    init?(ttml: String) {
        guard let root = TTMLDocument.parse(ttml) else { return nil }
        var values: [String: String] = [:]
        for node in root.descendants(where: { $0.localName == "meta" }) {
            guard let key = node.attribute("key"),
                  let value = node.attribute("value") else { continue }
            values[key] = value
        }
        ncmMusicID = values["ncmMusicId"].flatMap(Int.init)
        musicName = Self.nonempty(values["musicName"])
        artists = Self.nonempty(values["artists"])
    }

    func matches(song: LyricSongMetadata) -> Bool {
        let musicName = musicName.map(Self.normalized) ?? ""
        let artists = artists.map(Self.normalized) ?? ""
        guard !musicName.isEmpty || !artists.isEmpty else { return true }

        let songTitle = Self.normalized(song.title)
        let cleanedSongTitle = Self.normalized(
            Self.removingParentheticalContent(from: song.title)
        )
        var titlesMatch = false
        if !musicName.isEmpty {
            let cleanedMusicName = Self.normalized(
                Self.removingParentheticalContent(from: musicName)
            )
            titlesMatch = Self.roughlyMatches(songTitle, musicName)
                || (!cleanedSongTitle.isEmpty
                    && Self.roughlyMatches(cleanedSongTitle, cleanedMusicName))
        }
        let artistsMatch = artists.isEmpty || song.artist.isEmpty
            || Self.sharesArtist(artists, with: Self.normalized(song.artist))
        if musicName.isEmpty { return artistsMatch }
        if artists.isEmpty { return titlesMatch }
        return titlesMatch || artistsMatch
    }

    private static func sharesArtist(_ candidate: String,
                                     with reference: String) -> Bool {
        let candidateNames = artistNames(from: candidate)
        let referenceNames = artistNames(from: reference)
        guard !candidateNames.isEmpty, !referenceNames.isEmpty else { return false }
        return referenceNames.contains { referenceName in
            candidateNames.contains { candidateName in
                roughlyMatches(candidateName, referenceName)
            }
        }
    }

    private static func roughlyMatches(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
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

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
