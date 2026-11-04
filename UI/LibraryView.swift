import SwiftUI
import Support
import TelegramDesignSystem
import TdSession
import UIKit

/// M2: the library, wearing Telegram's chat-list clothing, in the mode the whole shell is
/// measured in — dark, true black, one hairline colour from the bar to the rules.
///
/// The chrome is `ChatListUI`'s at the app's own scale — a 72 pt row, the icon column
/// 16 pt from the edge and the text pinned at 86 whatever stands in that column, the title 8 pt
/// below the top of the row rather than centred, one physical pixel for the rule, and `#121212`
/// under a finger (`DefaultDarkPresentationTheme.swift:484`). Above it floats `GlassBar`, the
/// pill the device asked the photo's band to become. What stands in the icon column
/// is the track's own
/// cover: the sharp 600×600 file Telegram already holds on the server when it has one
/// (`external_album_covers`), the 40×30 `minithumbnail` the message carried when it does not, and
/// the avatar gradient when there is no artwork at all. A tap hands the track to `Player`.
/// Numbers and their lines are in `Docs/design-tokens.md`.
struct LibraryView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.displayScale) private var displayScale
    @Environment(\.telegramFloatingClearance) private var floatingClearance

    @State private var showsAccountMenu = false

    private let palette = TelegramPalette.dark

    var body: some View {
        ZStack(alignment: .top) {
            rows
            LargeTitleHeader(title: "Thư viện", actions: [
                HeaderAction(symbol: "shuffle", label: "Phát ngẫu nhiên") {
                    shuffleAll()
                },
                HeaderAction(symbol: "arrow.clockwise", label: "Đọc lại kênh") {
                    indexer.run(session, library: library)
                },
                HeaderAction(symbol: "ellipsis", label: "Kênh và tài khoản") {
                    showsAccountMenu = true
                },
            ])
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .task {
            player.bind(session.covers())
            indexer.run(session, library: library)
        }
        .confirmationDialog(
            "Tài khoản",
            isPresented: $showsAccountMenu,
            titleVisibility: .visible
        ) {
            if indexer.isReading {
                Button("Dừng đọc kênh", role: .destructive) { indexer.stop() }
            } else {
                Button("Tải lại thư viện") { indexer.run(session, library: library) }
            }
            Button("Đăng xuất", role: .destructive) { session.logOut() }
            Button("Huỷ", role: .cancel) {}
        }
    }

    // MARK: Chrome

    /// The shuffle the trailing group's first item runs: the whole library, in an order that is
    /// not the channel's. Telegram's own bar actions are one tap each, so this starts immediately
    /// rather than asking.
    private func shuffleAll() {
        var list = indexer.tracks
        guard !list.isEmpty else { return }
        list.shuffle()
        player.play(list[0], in: list)
    }

    // MARK: List

    private var rows: some View {
        let visible = indexer.tracks
        // The hearts are read off the published list rather than queried per row: a redraw
        // touches every visible row, and a thousand lookups for it is a lot of SQL for a screen.
        let kept = Set(library.favorites.map { $0.track.uniqueId })
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visible, id: \.uniqueId) { track in
                    TrackRow(
                        track: track,
                        query: "",
                        hairline: TelegramGeometry.hairline(displayScale: displayScale),
                        palette: palette,
                        isCurrent: player.current?.uniqueId == track.uniqueId,
                        isPlaying: player.current?.uniqueId == track.uniqueId && player.isPlaying,
                        headline: track.headline,
                        isFavorite: kept.contains(track.uniqueId),
                        artwork: artwork
                    ) {
                        player.play(track, in: Array(visible))
                    }
                    .trackActions(track, library: library)
                    .transition(.offset(y: 6).combined(with: .opacity))
                    .task(id: track.uniqueId) {
                        await artwork.load(track: track, via: session.covers())
                    }
                }
                footer()
            }
        }
        // The list runs under the header, the way the reference's collection does under its bar;
        // the clearance is what the first row needs to start below the title and what the last
        // row needs to finish above the tab bar.
        .contentMargins(.top, TelegramHeaderMetrics.topClearance, for: .scrollContent)
        .contentMargins(.bottom, floatingClearance, for: .scrollContent)
        .refreshable { await indexer.reload(session, library: library) }
        .animation(TelegramLoginMotion.easeInOut(0.2), value: visible.map(\.uniqueId))
    }

    /// Telegram's list ends in blank white, so what the end of this list says is Doni's own —
    /// but it says it in the list's own fonts and greys.
    @ViewBuilder
    private func footer() -> some View {
        if indexer.tracks.isEmpty {
            if indexer.isReading {
                VStack(spacing: 12) {
                    Spinner(color: palette.navControl, side: 24)
                    Text(indexer.statusLine.isEmpty ? "Đang đọc kênh…" : indexer.statusLine)
                        .font(TelegramLibraryTypography.preview)
                        .foregroundStyle(palette.chatListMessageText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
            } else if let failure = indexer.failureLine {
                VStack(spacing: 14) {
                    Text(failure)
                        .font(TelegramLibraryTypography.preview)
                        .foregroundStyle(palette.chatListMessageText)
                        .multilineTextAlignment(.center)
                    Button("Thử lại") { indexer.run(session, library: library) }
                        .font(TelegramLibraryTypography.barTitle)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 40)
                        .background(Capsule().fill(palette.highlight))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
                .padding(.horizontal, 40)
            } else {
                Text("Chưa có bài nào trong kênh")
                    .font(TelegramLibraryTypography.preview)
                    .foregroundStyle(palette.chatListMessageText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 72)
            }
        } else if let failure = indexer.failureLine {
            // Reading can fail into a half-filled library, and the bar no longer has room to say
            // so, so the end of the list does.
            HStack(spacing: 8) {
                Text(failure)
                    .font(TelegramLibraryTypography.preview)
                    .foregroundStyle(palette.chatListDraftText)
                Button("Thử lại") { indexer.run(session, library: library) }
                    .font(TelegramLibraryTypography.preview)
                    .foregroundStyle(palette.highlight)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if indexer.isReading {
            HStack(spacing: 8) {
                Spinner(color: palette.navControl)
                Text(indexer.statusLine)
            }
            .font(TelegramLibraryTypography.preview)
            .foregroundStyle(palette.chatListMessageText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

#Preview {
    LibraryView(
        session: TelegramSession(),
        indexer: LibraryIndexer(),
        player: Player(),
        artwork: CoverArtwork.shared,
        library: Library.shared
    )
}
