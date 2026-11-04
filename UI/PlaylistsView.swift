import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The playlists tab, after MeloX: a plain list of 54 pt covers at radius 7, the name over
/// "n bài" in `caption` secondary, a swipe to delete and a "+" that opens a medium sheet
/// (`LibraryPlaylistsView.swift:14-167`, `PlaylistCreationSheet.swift`).
struct PlaylistsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.displayScale) private var displayScale
    @Environment(\.telegramFloatingClearance) private var floatingClearance

    /// Playlist ids, so the detail level is a value rather than a view: the tab has to be able to
    /// open whatever list the store last said exists.
    @State private var path: [Int64] = []
    @State private var naming: Naming?
    /// The cover each list wears, read once per row rather than on every redraw.
    @State private var covers: [Int64: StoreTrack] = [:]
    /// The reference does not throw a list away on a swipe: it asks, with the name in the message
    /// (`LibraryPlaylistsView.swift:63-78`).
    @State private var pendingDeletion: StoredPlaylist?

    private let palette = TelegramPalette.dark

    /// What the naming sheet is doing: a list being made, or an existing one being renamed.
    private enum Naming: Equatable, Identifiable {
        case create
        case rename(Int64, String)

        var id: String {
            switch self {
            case .create: return "create"
            case let .rename(id, _): return "rename-\(id)"
            }
        }

        var title: String {
            switch self {
            case .create: return "Danh sách mới"
            case .rename: return "Đổi tên danh sách"
            }
        }

        var verb: String {
            switch self {
            case .create: return "Tạo"
            case .rename: return "Lưu"
            }
        }

        var initial: String {
            switch self {
            case .create: return ""
            case let .rename(_, name): return name
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                rows
                LargeTitleHeader(title: "Danh sách", actions: [
                    HeaderAction(symbol: "plus", label: "Danh sách mới") {
                        naming = .create
                    },
                ])
            }
            .background(palette.chatListBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)   // every level of this tab draws its own bar
            .navigationDestination(for: Int64.self) { id in
                PlaylistDetailView(playlistId: id, session: session, player: player,
                                   artwork: artwork, library: library)
            }
        }
        .sheet(item: $naming) { kind in
            PlaylistNameSheet(title: kind.title, verb: kind.verb, initial: kind.initial) { text in
                commit(kind, text)
            }
        }
        .confirmationDialog(
            "Xoá danh sách này?",
            isPresented: deletionPresented,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { list in
            Button("Xoá \(list.name)", role: .destructive) {
                library.deletePlaylist(id: list.id)
            }
            Button("Huỷ", role: .cancel) {}
        } message: { list in
            Text("“\(list.name)” có \(list.trackCount) bài.")
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } })
    }

    private func commit(_ kind: Naming, _ text: String) {
        switch kind {
        case .create:
            _ = library.createPlaylist(named: text)
        case let .rename(id, _):
            library.renamePlaylist(id: id, name: text)
        }
    }

    // MARK: List

    private var rows: some View {
        List {
            Section {
                ForEach(library.playlists) { list in
                    NavigationLink(value: list.id) {
                        PlaylistRow(playlist: list, cover: covers[list.id], artwork: artwork)
                            .task(id: list.id) {
                                let cover = library.firstTrack(in: list.id)
                                covers[list.id] = cover
                                if let cover {
                                    await artwork.load(track: cover, via: session.covers(),
                                                       side: MusicPlaylistMetrics.rowArt)
                                }
                            }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = list
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            naming = .rename(list.id, list.name)
                        } label: {
                            Label("Đổi tên", systemImage: "pencil")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, TelegramHeaderMetrics.topClearance, for: .scrollContent)
        .contentMargins(.bottom, floatingClearance, for: .scrollContent)
        .overlay {
            if library.playlists.isEmpty {
                ContentUnavailableView(
                    "Chưa có danh sách nào",
                    systemImage: "music.note.list",
                    description: Text("Nhấn + ở trên, hoặc nhấn giữ một bài trong Thư viện rồi "
                        + "chọn Danh sách mới.")
                )
                .allowsHitTesting(false)
            }
        }
    }
}

/// A playlist row, the way the reference builds one: a 54 pt cover at radius 7, 12 pt to a name
/// with the song count under it in `caption` at secondary (`LibraryPlaylistsView.swift:151-167`).
///
/// A Netease list carries its own artwork; Doni's carry the first song's, which is the only picture
/// a list here has. A list still empty wears the coverless gradient with the list glyph in it, the
/// way `TrackCover` dresses a song with no artwork.
private struct PlaylistRow: View {
    let playlist: StoredPlaylist
    let cover: StoreTrack?
    let artwork: CoverArtwork

    var body: some View {
        HStack(spacing: MusicPlaylistMetrics.rowSpacing) {
            if let cover {
                TrackCover(track: cover, side: MusicPlaylistMetrics.rowArt,
                           radius: MusicPlaylistMetrics.rowArtRadius, artwork: artwork)
            } else {
                ZStack {
                    TelegramTrackGradient.linear(playlist.id)
                    Image(systemName: "music.note.list")
                        .font(MusicArtworkMetrics.placeholderGlyph)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: MusicPlaylistMetrics.rowArt, height: MusicPlaylistMetrics.rowArt)
                .clipShape(RoundedRectangle(cornerRadius: MusicPlaylistMetrics.rowArtRadius,
                                            style: .continuous))
            }

            VStack(alignment: .leading, spacing: MusicPlaylistMetrics.rowTextGap) {
                Text(playlist.name)
                    .lineLimit(1)
                Text(playlist.trackCount == 0
                    ? "Chưa có bài nào"
                    : "\(playlist.trackCount.formatted()) bài")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
    }
}

/// One list, in the order the user put it together.
///
/// The rows are the library's rows, so a song looks the same here as anywhere else; what is
/// different is only the bar — a chevron back, the list's name where the channel's would be, and
/// a way to throw the whole list away.
private struct PlaylistDetailView: View {
    let playlistId: Int64
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.displayScale) private var displayScale
    @Environment(\.telegramFloatingClearance) private var floatingClearance
    @Environment(\.dismiss) private var dismiss

    /// Deleting a list is the one thing on this screen that costs the user work, so the bar's
    /// trash asks first.
    @State private var confirmsDelete = false

    private let palette = TelegramPalette.dark

    var body: some View {
        let tracks = library.tracks(in: playlistId)
        let kept = Set(library.favorites.map { $0.track.uniqueId })
        return ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
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
                            player.play(track, in: tracks.map { $0 as any Playable })
                        }
                        .trackActions(track, library: library) {
                            Button(role: .destructive) {
                                library.removeTrack(uniqueId: track.uniqueId, from: playlistId)
                            } label: {
                                Label("Bỏ khỏi danh sách", systemImage: "minus.circle")
                            }
                        }
                        .transition(.offset(y: 6).combined(with: .opacity))
                        .task(id: track.uniqueId) {
                            await artwork.load(track: track, via: session.covers())
                        }
                    }
                    if tracks.isEmpty {
                        Text("Danh sách này chưa có bài nào. Nhấn giữ một bài trong Thư viện rồi chọn "
                             + "một danh sách.")
                            .font(TelegramLibraryTypography.preview)
                            .foregroundStyle(palette.chatListMessageText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 72)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .contentMargins(.top, TelegramBarMetrics.topClearance, for: .scrollContent)
            .contentMargins(.bottom, floatingClearance, for: .scrollContent)
            .animation(TelegramLoginMotion.easeInOut(0.2), value: tracks.map(\.uniqueId))

            GlassBar(
                title: library.playlists.first { $0.id == playlistId }?.name ?? "",
                onBack: { dismiss() },
                actions: [
                    GlassBarAction(symbol: "trash", label: "Xoá danh sách") {
                        confirmsDelete = true
                    },
                ]
            )
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Xoá danh sách này?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Xoá", role: .destructive) {
                library.deletePlaylist(id: playlistId)
                dismiss()
            }
            Button("Huỷ", role: .cancel) {}
        }
    }
}

#Preview {
    PlaylistsView(
        session: TelegramSession(),
        player: Player(),
        artwork: CoverArtwork.shared,
        library: Library.shared
    )
}
