import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// Where the music lives, behind one door.
///
/// iOS 26 only gives the search tab its own circle outside the pill while the bar has room for it, and
/// five items is the ceiling. The two doors that are not the listener's own music — the channels they
/// subscribe to and the files they put in Saved Messages — can therefore live here instead, the way
/// MeloX keeps its cloud drive and its message box behind one row of the account panel. Each row pushes
/// the same screen the tab used to show, with its own stack and its own back button.
struct MoreView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    var body: some View {
        List {
            NavigationLink(value: MoreDoor.channels) {
                Label("Kênh", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(MusicTint.accent)
            }
            NavigationLink(value: MoreDoor.cloud) {
                Label("Cloud Music", systemImage: "icloud")
                    .foregroundStyle(MusicTint.accent)
            }
        }
        .navigationTitle("Thêm")
        .navigationDestination(for: MoreDoor.self) { door in
            switch door {
            case .channels:
                ChannelsView(session: session, indexer: indexer, player: player,
                             artwork: artwork, library: library)
            case .cloud:
                CloudMusicView(session: session, player: player, artwork: artwork,
                               library: library)
            }
        }
    }
}

/// The two doors, as routing values rather than tab selections — which is what lets one of them also be
/// lifted into the bar when the listener asks for it.
enum MoreDoor: Hashable {
    case channels
    case cloud
}

extension DoniTab {
    /// The door this tab is behind when it is not in the bar.
    var door: MoreDoor? {
        switch self {
        case .channels: .channels
        case .cloud: .cloud
        default: nil
        }
    }

    /// The screen the tab shows, whether it is reached from the bar or from "Thêm".
    @ViewBuilder func screen(session: TelegramSession, indexer: LibraryIndexer, player: Player,
                             artwork: CoverArtwork, library: Library) -> some View {
        switch self {
        case .channels:
            ChannelsView(session: session, indexer: indexer, player: player,
                         artwork: artwork, library: library)
        case .cloud:
            CloudMusicView(session: session, player: player, artwork: artwork, library: library)
        default:
            EmptyView()
        }
    }
}

/// Which of the two movable doors also stands in the bar.
///
/// The reference lets the listener choose where each tab lives (`NavigationPreferences.swift:22-60`),
/// and Doni keeps the same choice — narrowed to one slot, because the bar cannot take more than four
/// tabs plus the search circle without folding the fifth into an overflow of its own. Choosing a second
/// one moves the first back behind "Thêm".
enum DoniTabPlacement {
    private static let key = "tabs.barExtra"

    /// The tab the listener lifted into the bar, if any.
    static var barExtra: DoniTab? {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let tab = DoniTab(rawValue: raw),
              tab.door != nil else { return nil }
        return tab
    }

    static func setBarExtra(_ tab: DoniTab?) {
        if let tab {
            UserDefaults.standard.set(tab.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The settings row's options: the doors, plus "none of them".
    static var choices: [(title: String, tab: DoniTab?)] {
        [("Kênh", .channels), ("Cloud Music", .cloud)]
    }
}
