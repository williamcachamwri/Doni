import AppKit
import SwiftUI
import TelegramDesignSystem

/// The desktop's root. Sidebar, main column, and the trailing panel the reference's Music-shaped chrome
/// grows the window for.
///
/// The window behaviour is the copied part — `DesktopMainWindowConfiguration` is the reference's file,
/// byte for byte, including its 258-point expansion before the panel mounts. The *content* of the three
/// columns is not: the reference's panes bind to NetEase view-models, and Doni's rows come out of
/// SQLite through `Library`, so each pane is written against what this app actually has.
struct DesktopRootView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var library: Library
    @ObservedObject var player: Player
    @State private var ui = DesktopUIState()
    @State private var isFullScreen = false

    private var inspectorShown: Bool {
        ui.inspector != nil
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .inspector(isPresented: .constant(inspectorShown)) {
            inspector
                .inspectorColumnWidth(min: 258, ideal: 258, max: 420)
        }
        .background(
            DesktopMainWindowConfiguration(
                isPlayerSidePanelPresented: inspectorShown,
                isPlayerPresented: player.current != nil,
                isFullScreen: $isFullScreen
            )
        )
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                ForEach(DesktopInspector.allCases) { panel in
                    Button {
                        ui.toggleInspector(panel)
                    } label: {
                        Label(panel.title, systemImage: panel.systemImage)
                    }
                    .tint(ui.inspector == panel ? MusicTint.accent : nil)
                }
            }
        }
    }

    private var sidebar: some View {
        List(selection: $ui.selection) {
            ForEach(visibleSections) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        // The phone's accent, not the system's: a blue selection in a red app is how a port advertises
        // that its chrome was not chosen.
        .tint(MusicTint.accent)
        .navigationSplitViewColumnWidth(min: 190, ideal: 226, max: 300)
    }

    /// A section the library has nothing for stays out of the list, except the doors that create the
    /// thing — an empty channel list is a reason to add a channel, not to hide the entry.
    private var visibleSections: [DesktopSection] {
        DesktopSection.allCases.filter { section in
            if section.alwaysVisible { return true }
            switch section {
            case .recent: return !library.recentlyPlayed.isEmpty
            case .downloaded: return library.downloadedCount > 0
            default: return true
            }
        }
    }

    private var detail: some View {
        Group {
            if !session.hasAnswered {
                ProgressView()
            } else if !session.isAuthorized {
                DesktopLoginView(session: session)
            } else {
                ContentUnavailableView(
                    ui.selection.title,
                    systemImage: ui.selection.systemImage,
                    description: Text(countLine)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(ui.selection.title)
    }

    /// The library's own numbers, so the shell is honest about being a shell: the counts are real rows,
    /// only the panes that list them are missing.
    private var countLine: String {
        switch ui.selection {
        case .home, .search: "\(library.trackCount) bài"
        case .recent: "\(library.recentlyPlayed.count) bài"
        case .liked: "\(library.favorites.count) bài"
        case .playlists: "\(library.playlists.count) danh sách"
        case .channels: "\(library.channels.count) kênh"
        case .cloud: "Saved Messages"
        case .downloaded: "\(library.downloadedCount) bài trên máy"
        }
    }

    private var inspector: some View {
        List {
            if let track = player.current {
                Label(track.displayTitle, systemImage: "music.note")
                Text(ui.inspector == .queue ? "Hàng đợi" : "Lời bài hát")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Chưa phát bài nào.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
