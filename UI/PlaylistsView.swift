import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The playlists tab, after MeloX: a plain list of 54 pt covers at radius 7, the name over
/// "n bài" in `caption` secondary, a swipe to delete and a "+" that opens a medium sheet
/// (`LibraryPlaylistsView.swift:14-167`, `PlaylistCreationSheet.swift`), and a detail screen whose
/// hero is a 68 %-wide cover under a glass row of shuffle / play / delete
/// (`PlaylistDetailContent.swift:176-228`, `:316-410`).
struct PlaylistsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var naming: Naming?
    /// The cover each list wears, read once per row rather than on every redraw.
    @State private var covers: [Int64: StoreTrack] = [:]
    /// The reference does not throw a list away on a swipe: it asks, with the name in the message
    /// (`LibraryPlaylistsView.swift:63-78`).
    @State private var pendingDeletion: StoredPlaylist?

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
        .background(TelegramPalette.dark.chatListBackground.ignoresSafeArea())
        .navigationTitle("Danh sách")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    naming = .create
                } label: {
                    Label("Danh sách mới", systemImage: "plus").labelStyle(.iconOnly)
                }
            }
        }
        .navigationDestination(for: Int64.self) { id in
            PlaylistDetailView(playlistId: id, session: session, player: player,
                               artwork: artwork, library: library)
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

/// One list, opened the way MeloX opens one: a blurred cover behind the whole screen, the hero at
/// the head of the scroll, and the songs under it (`PlaylistDetailContent.swift:33-100`).
private struct PlaylistDetailView: View {
    let playlistId: Int64
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var query = ""
    @State private var confirmsDelete = false
    /// Renaming happens on the sheet the tab already owns, reached from the bar's menu.
    @State private var renaming = false

    private let palette = TelegramPalette.dark

    var body: some View {
        let tracks = visible
        ZStack {
            backdrop
            ScrollView {
                LazyVStack(spacing: 0) {
                    hero(tracks)
                    ForEach(tracks) { track in
                        TrackRow(
                            track: track,
                            query: query,
                            hairline: TelegramGeometry.hairline(displayScale: displayScale),
                            palette: palette,
                            isCurrent: player.current?.uniqueId == track.uniqueId,
                            isPlaying: player.current?.uniqueId == track.uniqueId && player.isPlaying,
                            headline: track.headline,
                            isFavorite: library.isFavorite(track.uniqueId),
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, MusicPlaylistMetrics.detailBottom)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: cover?.uniqueId) {
            // The hero and the backdrop both draw at a width no row ever asked for, so without this
            // order the list's own cover stays the 192 px a 54 pt row fetched and both surfaces fall
            // back to the gradient.
            if let cover {
                await artwork.load(track: cover, via: session.covers(),
                                   side: MusicArtworkMetrics.heroSide)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm trong danh sách")
        .animation(TelegramLoginMotion.easeInOut(0.2), value: tracks.map(\.uniqueId))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renaming = true
                    } label: {
                        Label("Đổi tên", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("Xoá danh sách", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Khác")
            }
        }
        .sheet(isPresented: $renaming) {
            PlaylistNameSheet(title: "Đổi tên danh sách", verb: "Lưu",
                              initial: name) { text in
                library.renamePlaylist(id: playlistId, name: text)
            }
        }
        .confirmationDialog("Xoá danh sách này?", isPresented: $confirmsDelete,
                            titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                library.deletePlaylist(id: playlistId)
                dismiss()
            }
            Button("Huỷ", role: .cancel) {}
        }
    }

    private var name: String {
        library.playlists.first { $0.id == playlistId }?.name ?? ""
    }

    private var cover: StoreTrack? {
        library.firstTrack(in: playlistId)
    }

    /// The list's own songs with the field's fold applied — the same toneless match the library
    /// uses, so "tinh yeu" finds "Tình yêu".
    private var visible: [StoreTrack] {
        let all = library.tracks(in: playlistId)
        let key = SearchTextFold.normalized(query)
        guard !key.isEmpty else { return all }
        return all.filter {
            SearchTextFold.normalized(
                "\($0.displayTitle) \($0.displayPerformer) \($0.fileName)"
            ).contains(key)
        }
    }

    /// MeloX blurs the cover over a palette read from it; Doni reads the average the same way the
    /// player's backdrop does and, with no cover yet, wears the list's own gradient
    /// (`PlaylistDetailContent.swift:442-487`).
    private var backdrop: some View {
        TelegramTrackGradient.linear(playlistId)
            .overlay {
                if let cover, let image = artwork.image(for: cover,
                                                         side: MusicArtworkMetrics.heroSide) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.22)
                }
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.24), .black.opacity(0.40)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    /// The hero: cover, name, count, and the glass row that plays them
    /// (`PlaylistDetailContent.swift:176-228`).
    private func hero(_ tracks: [StoreTrack]) -> some View {
        VStack(spacing: 0) {
            heroArt
                .shadow(color: .black.opacity(MusicPlaylistMetrics.heroShadowOpacity),
                        radius: MusicPlaylistMetrics.heroShadowRadius,
                        y: MusicPlaylistMetrics.heroShadowY)

            Text(name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, MusicPlaylistMetrics.heroArtToTitle)
                .padding(.horizontal, MusicPlaylistMetrics.heroSidePadding)

            Text("Danh sách của bạn")
                .font(.title3)
                .lineLimit(1)
                .padding(.top, MusicPlaylistMetrics.heroTitleToSubtitle)

            Text("\(tracks.count.formatted()) bài")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, MusicPlaylistMetrics.heroSubtitleToCount)

            MusicCollectionPrimaryActions(
                tracks: tracks.map { $0 as any Playable },
                onShuffle: { shuffle(tracks) },
                onPlayAll: { play(tracks) },
                onDelete: { confirmsDelete = true }
            )
            .padding(.top, MusicPlaylistMetrics.heroToActions)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MusicPlaylistMetrics.heroTop)
        .padding(.bottom, MusicPlaylistMetrics.heroBottom)
    }

    /// `min(width × 0.68, 300)` at radius 12, square — and in the reference's own modifier order,
    /// where the cap is applied by `containerRelativeFrame` *before* the aspect ratio reads the
    /// proposal (`PlaylistDetailContent.swift:190-193`, `ArtworkImage.swift:12-29`). Measuring the
    /// cap inside the `GeometryReader` instead leaves the ratio pinning a full-screen-height square,
    /// which is the empty band the hero used to show.
    @ViewBuilder
    private var heroArt: some View {
        GeometryReader { proxy in
            if let cover {
                TrackCover(track: cover, side: proxy.size.width,
                           radius: MusicPlaylistMetrics.heroArtRadius, artwork: artwork)
            } else {
                ZStack {
                    TelegramTrackGradient.linear(playlistId)
                    Image(systemName: "music.note.list")
                        .font(MusicArtworkMetrics.placeholderGlyph)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .clipShape(RoundedRectangle(cornerRadius: MusicPlaylistMetrics.heroArtRadius,
                                            style: .continuous))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .containerRelativeFrame(.horizontal) { width, _ in
            min(width * MusicPlaylistMetrics.heroWidthFactor, MusicArtworkMetrics.heroSide)
        }
    }

    private func play(_ tracks: [StoreTrack]) {
        guard let first = tracks.first else { return }
        player.play(first, in: tracks.map { $0 as any Playable })
    }

    private func shuffle(_ tracks: [StoreTrack]) {
        guard !tracks.isEmpty else { return }
        let list = tracks.map { $0 as any Playable }
        player.play(list[Int.random(in: 0..<list.count)], in: list.shuffled())
    }
}

/// The hero's three buttons, in the container that lets the glass share one refraction
/// (`PlaylistDetailContent.swift:316-410`).
///
/// MeloX's third slot saves the list to the library; Doni's lists are already the user's, so it
/// deletes instead — same 30 pt circle, same glass.
private struct MusicCollectionPrimaryActions: View {
    let tracks: [any Playable]
    let onShuffle: () -> Void
    let onPlayAll: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: MusicPlaylistMetrics.actionGap) {
            HStack(spacing: MusicPlaylistMetrics.actionGap) {
                Button(action: onShuffle) {
                    Image(systemName: "shuffle")
                        .font(.title2.weight(.semibold))
                        .frame(width: MusicPlaylistMetrics.actionGlyph,
                               height: MusicPlaylistMetrics.actionGlyph)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(tracks.isEmpty)
                .accessibilityLabel("Phát ngẫu nhiên")

                Button(action: onPlayAll) {
                    Label("Phát", systemImage: "play.fill")
                        .font(.title3.weight(.bold))
                        .frame(minWidth: 116)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(tracks.isEmpty)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.title2.weight(.semibold))
                        .frame(width: MusicPlaylistMetrics.actionGlyph,
                               height: MusicPlaylistMetrics.actionGlyph)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Xoá danh sách")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlaylistsView(
            session: TelegramSession(),
            player: Player(),
            artwork: CoverArtwork.shared,
            library: Library.shared
        )
    }
}
