import Foundation
import Observation

/// The sidebar's destinations.
///
/// The reference's list is NetEase's — radio, podcasts, albums, artists, private messages — and Doni has
/// none of those, so the cases are the phone's own screens. What is taken from `DesktopNavigation` is the
/// shape: one enum that carries its own title, glyph and gating, and a UI state whose path clears when
/// the section changes.
enum DesktopSection: String, CaseIterable, Identifiable, Hashable {
    case search
    case home
    case recent
    case liked
    case playlists
    case channels
    case cloud
    case downloaded

    var id: Self { self }

    /// Vietnamese is the development language, so the literal is the catalog key
    /// (`Scripts/strings.txt`), exactly as the phone's views do it.
    ///
    /// It is a *key*, not a display string: a render site that hands this to `Tab(_:)` or
    /// `navigationTitle(_:)` as a plain `String` draws Vietnamese in every language, so those sites wrap
    /// it in `localized(_:)`.
    var title: String {
        switch self {
        case .search: "Tìm kiếm"
        case .home: "Trang chủ"
        case .recent: "Gần đây"
        case .liked: "Yêu thích"
        case .playlists: "Danh sách"
        case .channels: "Kênh"
        case .cloud: "Cloud Music"
        case .downloaded: "Đã tải"
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .home: "house"
        case .recent: "clock"
        case .liked: "heart"
        case .playlists: "music.note.list"
        case .channels: "antenna.radiowaves.left.and.right"
        case .cloud: "icloud"
        case .downloaded: "arrow.down.circle"
        }
    }

    /// Rows the sidebar shows even when the library has none yet — an empty channel list is a reason to
    /// add one, not a reason to hide the door.
    var alwaysVisible: Bool {
        switch self {
        case .search, .home, .liked, .playlists, .channels, .cloud: true
        case .recent, .downloaded: false
        }
    }
}

/// Where the main column goes beyond its section.
///
/// The reference routes by NetEase's numeric ids; Doni's rows are keyed by TDLib's durable
/// `file_unique_id` and its chats by `chat_id`, so the payloads differ while the mechanism — a path,
/// cleared when the section changes — is the same one.
enum DesktopRoute: Hashable {
    case playlist(Int64)
    case channel(chatId: Int64, title: String)
}

/// One song waiting to be filed into a list.
///
/// The naming lives with the shell rather than with the row that asked, because the same verb is on the
/// list rows, the bar's ⋯ and the player's ⋯, and a sheet that opens from three places cannot belong to
/// any of them. Keyed by the song's own durable id so `sheet(item:)` can drive it.
struct DesktopPlaylistTarget: Identifiable, Equatable {
    let track: any Playable

    var id: String { track.uniqueId }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// The trailing panel. Two of them, exactly as the reference has them, because lyrics and up-next are
/// different questions about the same song.
enum DesktopInspector: String, CaseIterable, Identifiable, Hashable {
    case lyrics
    case queue

    var id: Self { self }

    var title: String {
        switch self {
        case .lyrics: "Lời bài hát"
        case .queue: "Hàng đợi"
        }
    }

    var systemImage: String {
        switch self {
        case .lyrics: "text.quote"
        case .queue: "list.bullet"
        }
    }
}

/// A panel that lifts off the shell rather than replacing it.
///
/// The reference has eight of these (`DesktopNavigation.swift:100-123`); Doni has the one the sidebar's
/// footer opens, because the rest — sleep timer, song recognition, listen-together — are things this app
/// does not do.
enum DesktopSheet: Identifiable {
    case account

    var id: String {
        switch self {
        case .account: "account"
        }
    }
}

@MainActor
@Observable
final class DesktopUIState {
    var selection: DesktopSection = .home {
        didSet { path.removeAll() }
    }
    var path: [DesktopRoute] = []
    var inspector: DesktopInspector?
    var sheet: DesktopSheet?
    /// Set by any ⋯ that offers "make a new list"; the shell owns the sheet it opens.
    var playlistTarget: DesktopPlaylistTarget?
    private(set) var retainedInspector: DesktopInspector = .lyrics
    var isNowPlayingPresented = false

    func navigate(to route: DesktopRoute) {
        path.append(route)
    }

    /// Closing the panel remembers what was open, so reopening it returns to the panel the listener had
    /// chosen rather than the default.
    func toggleInspector(_ requested: DesktopInspector) {
        if inspector == requested {
            inspector = nil
        } else {
            retainedInspector = requested
            inspector = requested
        }
    }
}
