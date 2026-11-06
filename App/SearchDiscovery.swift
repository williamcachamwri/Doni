import Foundation

// Moved out of `UI/SearchDiscoveryView.swift` verbatim: the indexer groups songs by performer, and a
// model file reaching into a view file for the type it groups into is the wrong direction. It also
// happens to be the reason the desktop could not compile the indexer at all.

/// One artist's name and the songs carrying it — the facet a Telegram channel has in place of genres.
struct SearchArtist: Identifiable {
    let name: String
    let tracks: [any Playable]

    var id: String { name }

    /// An artist's artwork is the artwork of a song it is on; the first is the newest.
    var sample: any Playable { tracks[0] }
}

extension Array where Element == any Playable {
    /// Grouped by performer, biggest first, then by name — MeloX's category order before filtering.
    var searchArtists: [SearchArtist] {
        var grouped: [String: [any Playable]] = [:]
        for track in self where !track.displayPerformer.trimmedSearchName.isEmpty {
            grouped[track.displayPerformer.trimmedSearchName, default: []].append(track)
        }
        return grouped.map { SearchArtist(name: $0.key, tracks: $0.value) }
            .sorted { lhs, rhs in
                lhs.tracks.count == rhs.tracks.count ? lhs.name < rhs.name
                                                      : lhs.tracks.count > rhs.tracks.count
            }
    }
}

extension String {
    /// Performer fields are bot-written text padded with spaces; an empty one is truly empty once the
    /// pad is gone.
    var trimmedSearchName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
