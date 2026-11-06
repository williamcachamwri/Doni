import Support
import SwiftUI
import TelegramDesignSystem

/// The sidebar, in the shape the reference has it (`DesktopSidebar.swift`).
///
/// This is not a `List` inside a `NavigationSplitView`, and the difference is the whole point: a
/// `.sidebarAdaptable` `TabView` gives every section its own page and its own navigation stack, so
/// stepping out of a channel's list back into the library does not unwind where the listener had got
/// to, and the column that draws it is AppKit's own — its width, its selection, its material.
///
/// What Doni changes is only what the reference could not know: the sections are Doni's, the footer
/// shows a Telegram account rather than a NetEase one, and the line above it reports the walk through
/// the channels rather than an HTTP request.
struct DesktopSidebar: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var session: TelegramSession
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var indexer: LibraryIndexer
    @State private var sidebarFrame = CGRect(x: 8, y: 8, width: 199, height: 0)

    private let primarySections: [DesktopSection] = [.search, .home]
    private let librarySections: [DesktopSection] = [
        .liked, .playlists, .channels, .cloud, .downloaded, .recent,
    ]

    var body: some View {
        @Bindable var ui = model.ui

        TabView(selection: $ui.selection) {
            ForEach(visible(primarySections)) { section in
                tab(for: section)
            }

            TabSection("Thư viện") {
                ForEach(visible(librarySections)) { section in
                    tab(for: section)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay(alignment: .bottomLeading) {
            pinnedFooter
                .frame(width: max(sidebarFrame.width, 1))
                .padding(.leading, max(sidebarFrame.minX, 0))
                .padding(.bottom, max(sidebarFrame.minY, 0))
        }
        .toolbar(removing: .sidebarToggle)
        .background {
            DesktopSidebarVisibilityLock(
                sidebarFrame: $sidebarFrame,
                reservedBottomInset: pinnedFooterHeight
            )
            .frame(width: 0, height: 0)
        }
    }

    /// A section the library has nothing for stays out of the list — except the doors that *create* the
    /// thing, and except the one the listener is standing in, which would otherwise vanish under them
    /// the moment its last row went.
    private func visible(_ sections: [DesktopSection]) -> [DesktopSection] {
        sections.filter { section in
            if section == model.ui.selection || section.alwaysVisible { return true }
            switch section {
            case .recent: return !library.recentlyPlayed.isEmpty
            case .downloaded: return library.downloadedCount > 0
            default: return true
            }
        }
    }

    private var pinnedFooterHeight: CGFloat {
        loadingMessage == nil ? 50 : 86
    }

    private var pinnedFooter: some View {
        VStack(spacing: 0) {
            if let loadingMessage {
                Text(loadingMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.horizontal, 10)
                    .transition(.opacity)
            }

            DesktopSidebarAccountFooter()
        }
        .animation(.easeInOut(duration: 0.18), value: loadingMessage)
    }

    /// The one place that answers "why is the list not full yet" without a banner anywhere else on the
    /// screen. Each branch is a different thing happening: a walk that gave up, a walk still reading, an
    /// account whose `getMe` has not landed, a file still arriving from Telegram.
    ///
    /// Every sentence here is resolved through `localized(_:)` rather than left as a literal, because a
    /// `String` handed to `Text` is drawn exactly as written — the row would be Vietnamese in Beijing.
    private var loadingMessage: String? {
        if session.isAuthorized, let failure = indexer.failureLine { return failure }
        if indexer.isReading { return indexer.statusLine }
        if session.isAuthorized && session.account == nil { return localized("Đang đăng nhập…") }
        if player.isFetchingFile { return localized("Đang tải bài hát…") }
        return nil
    }

    /// `title` is a catalog key, not a display string: `Tab(_:systemImage:value:)` handed a `String`
    /// renders it verbatim, so the lookup has to happen here.
    private func tab(for section: DesktopSection) -> some TabContent<DesktopSection> {
        Tab(localized(section.title), systemImage: section.systemImage, value: section) {
            DesktopTabPage(section: section)
                .toolbar(removing: .sidebarToggle)
        }
    }
}

/// The account button, which is the reference's footer (`DesktopSidebar.swift:141-175`) with Telegram's
/// answer in it: `getMe` gives the name and the 160 px picture the session already fetched gives the
/// face — the same two the phone's header draws.
struct DesktopSidebarAccountFooter: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var session: TelegramSession

    var body: some View {
        Button {
            model.ui.sheet = .account
        } label: {
            HStack(spacing: 9) {
                DesktopAccountMark(size: 30)

                name
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(height: 50)
    }

    private var name: Text {
        guard let account = session.account else {
            return Text("Chưa đăng nhập")
        }
        return Text(account.name)
    }
}
