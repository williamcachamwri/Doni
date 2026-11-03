import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The lists tab: playlists the user made.
///
/// Telegram has no counterpart — its music player only has saved music on the server
/// (`TelegramCore/Sources/TelegramEngine/Peers/SavedMusic.swift`), not a list you name yourself —
/// so the screen is Doni's own, and it spends what it has on chrome the reference *does* measure:
/// the same 68 pt row, the same 54 pt icon column, the same 84 pt text inset, the same one-pixel
/// rule inset to where the text begins.
struct PlaylistsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.displayScale) private var displayScale

    /// Playlist ids, so the detail level is a value rather than a view: the tab has to be able to
    /// open whatever list the store last said exists.
    @State private var path: [Int64] = []
    @State private var naming: Naming?
    @State private var name = ""

    private let palette = TelegramPalette.dark

    /// What the naming sheet is doing: a list being made, or an existing one being renamed.
    private enum Naming: Equatable {
        case create
        case rename(Int64, String)

        var verb: String {
            switch self {
            case .create: return "Tạo"
            case .rename: return "Lưu"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                rows
            }
            .background(palette.chatListBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)   // every level of this tab draws its own bar
            .navigationDestination(for: Int64.self) { id in
                PlaylistDetailView(playlistId: id, session: session, player: player,
                                   artwork: artwork, library: library)
            }
        }
        .alert(titleForAlert, isPresented: nameBeingEntered, presenting: naming) { kind in
            TextField("Tên danh sách", text: $name)
            Button(kind.verb) { commit(kind) }
            Button("Huỷ", role: .cancel) {}
        }
    }

    private var titleForAlert: String {
        naming == .create ? "Danh sách mới" : "Đổi tên danh sách"
    }

    private var nameBeingEntered: Binding<Bool> {
        Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })
    }

    private func commit(_ kind: Naming) {
        switch kind {
        case .create:
            _ = library.createPlaylist(named: name)
        case let .rename(id, _):
            library.renamePlaylist(id: id, name: name)
        }
        naming = nil
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    Text("Danh sách")
                        .font(TelegramLibraryTypography.barTitle)
                        .foregroundStyle(palette.navPrimaryText)
                    Text("\(library.playlists.count.formatted()) danh sách")
                        .font(TelegramLibraryTypography.barSubtitle)
                        .foregroundStyle(palette.navSecondaryText)
                }
                HStack {
                    Spacer()
                    Button {
                        name = ""
                        naming = .create
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(palette.navControl)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .accessibilityLabel("Danh sách mới")
                }
            }
            .frame(height: TelegramLibraryMetrics.navigationBarHeight)
        }
        .background(palette.navOpaqueBackground.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.navSeparator)
                .frame(height: TelegramGeometry.hairline(displayScale: displayScale))
        }
    }

    // MARK: List

    private var rows: some View {
        let lists = library.playlists
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(lists) { list in
                    Button {
                        path.append(list.id)
                    } label: {
                        PlaylistRow(
                            playlist: list,
                            hairline: TelegramGeometry.hairline(displayScale: displayScale),
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            name = list.name
                            naming = .rename(list.id, list.name)
                        } label: {
                            Label("Đổi tên", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            library.deletePlaylist(id: list.id)
                        } label: {
                            Label("Xoá danh sách", systemImage: "trash")
                        }
                    }
                }
                if lists.isEmpty {
                    Text("Chưa có danh sách nào. Nhấn + ở trên, hoặc nhấn giữ một bài trong Thư viện "
                         + "rồi chọn Danh sách mới.")
                        .font(TelegramLibraryTypography.preview)
                        .foregroundStyle(palette.chatListMessageText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 72)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(TelegramLoginMotion.easeInOut(0.2), value: lists.map(\.name))
    }
}

/// A playlist in the chat list's clothing, with the list's own artwork column empty of artwork:
/// the gradient Telegram gives a photoless peer, and the note glyph it gives audio.
private struct PlaylistRow: View {
    let playlist: StoredPlaylist
    let hairline: CGFloat
    let palette: TelegramPalette

    var body: some View {
        HStack(alignment: .top, spacing: TelegramLibraryMetrics.artToText) {
            ZStack {
                TelegramTrackGradient.linear(playlist.id)
                Image(systemName: "music.note.list")
                    .font(.system(size: TelegramLibraryMetrics.artGlyph, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: TelegramLibraryMetrics.artSide, height: TelegramLibraryMetrics.artSide)
            .clipShape(RoundedRectangle(cornerRadius: TelegramLibraryMetrics.artRadius,
                                        style: .continuous))
            .padding(.top, TelegramLibraryMetrics.artTop)

            VStack(alignment: .leading, spacing: TelegramLibraryMetrics.titleToPreview) {
                Text(playlist.name)
                    .font(TelegramLibraryTypography.title)
                    .foregroundStyle(palette.chatListTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(playlist.trackCount == 0
                    ? "Chưa có bài nào"
                    : "\(playlist.trackCount.formatted()) bài")
                    .font(TelegramLibraryTypography.preview)
                    .foregroundStyle(palette.chatListMessageText)
                    .lineLimit(1)
            }
            .padding(.top, TelegramLibraryMetrics.titleTop)
            .frame(maxWidth: .infinity, alignment: .leading)

            // The column every other row in the app has; a list has nothing to say in it, and the
            // text column still has to stop where the timestamp rows do.
            Color.clear
                .frame(width: TelegramLibraryMetrics.stateSide,
                       height: TelegramLibraryMetrics.stateSide)
                .padding(.top, TelegramLibraryMetrics.dateTop)
        }
        .padding(.leading, TelegramLibraryMetrics.leading)
        .padding(.trailing, TelegramLibraryMetrics.trailing)
        .frame(maxWidth: .infinity)
        .frame(height: TelegramLibraryMetrics.rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.chatListSeparator)
                .frame(height: hairline)
                .padding(.leading, TelegramLibraryMetrics.leading
                    + TelegramLibraryMetrics.artSide
                    + TelegramLibraryMetrics.artToText)
                .padding(.trailing, TelegramLibraryMetrics.trailing)
        }
        .contentShape(Rectangle())
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
    @Environment(\.dismiss) private var dismiss

    private let palette = TelegramPalette.dark

    var body: some View {
        let tracks = library.tracks(in: playlistId)
        let kept = Set(library.favorites.map { $0.track.uniqueId })
        return VStack(spacing: 0) {
            header
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
            .animation(TelegramLoginMotion.easeInOut(0.2), value: tracks.map(\.uniqueId))
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack {
            Text(library.playlists.first { $0.id == playlistId }?.name ?? "")
                .font(TelegramLibraryTypography.barTitle)
                .foregroundStyle(palette.navPrimaryText)
                .lineLimit(1)
                .padding(.horizontal, 48)
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.navControl)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        library.deletePlaylist(id: playlistId)
                        dismiss()
                    } label: {
                        Label("Xoá danh sách", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(palette.navControl)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .frame(height: TelegramLibraryMetrics.navigationBarHeight)
        .background(palette.navOpaqueBackground.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.navSeparator)
                .frame(height: TelegramGeometry.hairline(displayScale: displayScale))
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
