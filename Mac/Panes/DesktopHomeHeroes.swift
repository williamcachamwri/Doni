import SwiftUI
import TelegramDesignSystem

/// The home page's hero cards, in the reference's form (`DesktopHomeQuickActionsView.swift:271-375`):
/// a 3:4 card with 15 pt corners, one oversized glyph at 22% white sitting a little above the middle,
/// a wordmark in the top-right, then an eyebrow at 14/0.68, a title at 25 bold and a two-line subtitle
/// at 14/0.92 over a gradient that darkens the bottom to 0.78 black.
///
/// The six destinations are Doni's, because MeloX's six are NetEase recommendation engines this app
/// does not have and should not pretend to: what to listen to next, what was kept, what is on the
/// machine, what is in Saved Messages, which channels, which lists. The colours are the reference's,
/// paired to the action they already dressed.
enum DesktopHomeAction: String, CaseIterable, Identifiable {
    case resume, liked, downloaded, cloud, channels, playlists

    var id: Self { self }

    var eyebrow: String {
        switch self {
        case .resume: "Tiếp tục"
        case .liked: "Đã giữ"
        case .downloaded: "Offline"
        case .cloud: "Saved Messages"
        case .channels: "Nguồn nhạc"
        case .playlists: "Của bạn"
        }
    }

    var title: String {
        switch self {
        case .resume: "Nghe tiếp"
        case .liked: "Yêu thích"
        case .downloaded: "Đã tải về máy"
        case .cloud: "Cloud Music"
        case .channels: "Kênh"
        case .playlists: "Danh sách"
        }
    }

    /// Descriptions, not counts: a card's number would have to be read before it could be told, and
    /// Saved Messages is only walked when its own pane opens. The reference puts a sentence here too.
    var subtitle: String {
        switch self {
        case .resume: "Đang nghe dở"
        case .liked: "Những bài bạn đã giữ"
        case .downloaded: "Nghe được khi không có mạng"
        case .cloud: "Nhạc bạn tự đưa lên Telegram"
        case .channels: "Từ các kênh Telegram"
        case .playlists: "Do bạn xếp"
        }
    }

    var systemImage: String {
        switch self {
        case .resume: "play.circle"
        case .liked: "heart.fill"
        case .downloaded: "arrow.down.circle.fill"
        case .cloud: "icloud"
        case .channels: "antenna.radiowaves.left.and.right"
        case .playlists: "music.note.list"
        }
    }

    /// The reference's own pairs (`:68-83`), kept per kind of action rather than re-chosen.
    var backgroundColors: [Color] {
        switch self {
        case .resume: [.indigo, .blue, .mint]
        case .liked: [.orange, .red]
        case .downloaded: [.black, .indigo, .gray]
        case .cloud: [.red, .orange]
        case .channels: [.purple, .blue]
        case .playlists: [.teal, .indigo]
        }
    }

    var tint: Color {
        switch self {
        case .resume: .blue
        case .liked: .orange
        case .downloaded: .indigo
        case .cloud: .red
        case .channels: .purple
        case .playlists: .teal
        }
    }

    /// Only one of these plays something when pressed; the rest open a column.
    var startsPlayback: Bool { self == .resume }
}

/// The hero shelf. The reference's 200/20 card metrics (`DesktopHomeView.swift:8-10`) so a card is the
/// same size on both machines at the same window width.
struct DesktopHomeHeroes: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Player

    private static let minimumCardWidth: CGFloat = 200
    private static let spacing: CGFloat = 20

    var body: some View {
        let actions = visible
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Dành cho bạn")
                    .font(.system(size: 17, weight: .bold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.minimumCardWidth,
                                                      maximum: 260),
                                             spacing: Self.spacing)],
                          alignment: .leading, spacing: Self.spacing) {
                    ForEach(actions) { action in
                        DesktopHeroCard(action: action, width: nil) {
                            perform(action)
                        }
                    }
                }
            }
        }
    }

    /// A card with nothing behind it is not shown — except Cloud, whose destination exists whether or
    /// not it has been read yet: it is where a song gets uploaded from.
    private var visible: [DesktopHomeAction] {
        DesktopHomeAction.allCases.filter { action in
            switch action {
            case .cloud: true
            case .resume: !library.recentlyPlayed.isEmpty
            case .liked: !library.favorites.isEmpty
            case .downloaded: library.downloadedCount > 0
            case .playlists: !library.playlists.isEmpty
            case .channels: !library.channels.isEmpty
            }
        }
    }

    private func perform(_ action: DesktopHomeAction) {
        switch action {
        case .resume:
            let tracks = DesktopPanes.recent(model)
            guard let first = tracks.first else { return }
            player.play(first, in: tracks)
        case .liked:
            model.ui.selection = .liked
        case .downloaded:
            model.ui.selection = .downloaded
        case .cloud:
            model.ui.selection = .cloud
        case .channels:
            model.ui.selection = .channels
        case .playlists:
            model.ui.selection = .playlists
        }
    }
}

/// One card. `width` is left nil so the grid decides it; the height is always the reference's width×4/3.
struct DesktopHeroCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let action: DesktopHomeAction
    let width: CGFloat?
    let perform: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: perform) {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { box in
                    background(height: box.size.height)
                }
                .aspectRatio(3 / 4, contentMode: .fit)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        Label("Doni", systemImage: "music.note")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 5) {
                        Text(LocalizedStringKey(action.eyebrow))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))

                        Text(LocalizedStringKey(action.title))
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(.white)

                        Text(LocalizedStringKey(action.subtitle))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                    }
                }
                .padding(24)
            }
            .contentShape(.rect(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(action.startsPlayback
            ? localized("Phát “%@”", action.title)
            : localized("Mở “%@”", action.title))
        .scaleEffect(isHovered ? 1.012 : 1)
        .shadow(color: .black.opacity(isHovered ? 0.22 : 0.10),
                radius: isHovered ? 18 : 6, y: isHovered ? 9 : 3)
        .clipShape(.rect(cornerRadius: 15, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
    }

    /// The reference sizes the glyph from the card's own height (`:357-360`), so it keeps its proportion
    /// however wide the column gets.
    private func background(height: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: action.backgroundColors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: action.systemImage)
                .font(.system(size: min(height * 0.34, 150)))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.22))
                .offset(y: -height * 0.08)

            LinearGradient(colors: [action.tint.opacity(0.06), .clear, .black.opacity(0.78)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}
