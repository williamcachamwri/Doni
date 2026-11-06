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

@MainActor
@Observable
final class DesktopUIState {
    var selection: DesktopSection = .home {
        didSet { path.removeAll() }
    }
    var path: [DesktopRoute] = []
    var inspector: DesktopInspector?
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
