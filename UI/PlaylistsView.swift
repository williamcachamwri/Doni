import SwiftUI
import PhotosUI
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
                            // The row draws 54 pt but orders the hero's 300, which is the reference's
                            // prefetch on the card a zoom starts from
                            // (`MusicNavigationTransitions.swift:48-52, 65-68`).
                            .task(id: list.id) {
                                let cover = library.firstTrack(in: list.id)
                                covers[list.id] = cover
                                if let cover {
                                    await artwork.load(track: cover, via: session.covers(),
                                                       side: MusicArtworkMetrics.heroSide)
                                }
                            }
                    }
                    .musicMatchedTransitionSource(playlistID: list.id)
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
                .musicNavigationTransition(playlistID: id)
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
private struct PlaylistRow: View {
    let playlist: StoredPlaylist
    let cover: StoreTrack?
    let artwork: CoverArtwork

    var body: some View {
        HStack(spacing: MusicPlaylistMetrics.rowSpacing) {
            PlaylistArt(listId: playlist.id, coverPath: playlist.coverPath, cover: cover,
                        side: MusicPlaylistMetrics.rowArt,
                        radius: MusicPlaylistMetrics.rowArtRadius, artwork: artwork)

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

/// A list's picture, in the order this app can find one: the cover the user chose for it, then the
/// first song's, then the list's own gradient with the glyph in it.
///
/// Every Netease list carries server artwork of its own, so the reference has only the first tier
/// here; the other two are what a Telegram list forces, and they are drawn the way `TrackCover`
/// dresses a song with no artwork.
///
/// The search tab's discovery shelf wears the same picture, so this is not private to the tab.
struct PlaylistArt: View {
    /// The list's own number, which is what the coverless gradient is picked by.
    let listId: Int64
    /// The picture the user chose, if any.
    let coverPath: String?
    /// The first song's cover — the only artwork a Telegram list has by itself.
    let cover: StoreTrack?
    let side: CGFloat
    let radius: CGFloat
    let artwork: CoverArtwork

    var body: some View {
        ZStack {
            TelegramTrackGradient.linear(listId)
            if let coverPath, let image = artwork.image(at: coverPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let cover {
                TrackCover(track: cover, side: side, radius: radius, artwork: artwork)
            } else {
                Image(systemName: "music.note.list")
                    .font(MusicArtworkMetrics.placeholderGlyph)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// One list, opened the way MeloX opens one: the cover's own colours behind the whole screen, the
/// hero at the head of the scroll, and the songs numbered under it
/// (`PlaylistDetailContent.swift:33-100`, `PlaylistTrackList.swift:86-284`).
///
/// The reference does not dress this screen in a fixed dark surface. It averages the artwork, calls
/// the screen light or dark from that average (`ArtworkAccentColorProvider.swift:276-284`), and hands
/// the result to the background, the nav bar, the tab bar and every row — which is why a bright
/// cover makes it pale and a dark one near-black.
///
/// The search tab pushes this screen too, so it is not private to the tab.
struct PlaylistDetailView: View {
    let playlistId: Int64
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.dismiss) private var dismiss
    /// The phone's own appearance, which is only what the screen wears until its cover has been
    /// read (`PlaylistDetailView.swift:13`).
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var query = ""
    @State private var confirmsDelete = false
    /// Renaming happens on the sheet the tab already owns, reached from the bar's menu.
    @State private var renaming = false
    /// The cover is chosen in the system's own photo picker. It opens from a plain button rather
    /// than from a `PhotosPicker` inside the menu, because the menu closes the moment it is tapped
    /// and a presentation started from inside it has nothing left to present from.
    @State private var choosingCover = false
    @State private var coverChoice: PhotosPickerItem?
    /// A photo the app could not read is said out loud: the list would otherwise keep wearing the
    /// cover it already had and look like the tap did nothing.
    @State private var coverFailed = false
    /// What the cover has been read as. Nil until the first read lands; the cache is consulted
    /// behind it so a screen pushed over a cover already read never flashes through a colour change.
    @State private var assets: ArtworkDetailAssets?

    var body: some View {
        presentations(chrome)
    }

    /// The screen itself: the cover's colours behind, the hero and the list in front.
    ///
    /// Split from `body` because the whole thing is one expression to the type checker, and the
    /// reference's own detail screen is split the same way — a content view and a view that only
    /// carries chrome (`PlaylistDetailContent.swift:33-100`, `PlaylistDetailView.swift:68-273`).
    private var chrome: some View {
        let dressing = resolved
        return ZStack {
            MusicCollectionArtworkBackdrop(blurredArtwork: dressing.blurredBackdrop,
                                           palette: dressing.palette)
            trackScroll
        }
        .foregroundStyle(.primary)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(dressing.palette.colorScheme, for: .navigationBar, .tabBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm trong danh sách")
        .environment(\.colorScheme, dressing.palette.colorScheme)
        .task(id: cover?.uniqueId) {
            // The hero draws at a width no row ever asked for, so without this order the list's own
            // cover stays the 192 px a 54 pt row fetched and the hero falls back to the gradient.
            if let cover {
                await artwork.load(track: cover, via: session.covers(),
                                   side: MusicArtworkMetrics.heroSide)
            }
        }
        .task(id: PaletteRead(key: paletteKey, revision: artwork.revision)) {
            await readPalette()
        }
        .animation(MusicScreenMotion.contentSwap, value: visible.map(\.uniqueId))
        .toolbar { barMenu }
    }

    /// The hero and every song under it, in the reference's own order: hero, then a row per track
    /// with a rule after each but the last (`PlaylistDetailContent.swift:40-89`).
    private var trackScroll: some View {
        let tracks = visible
        return ScrollView {
            LazyVStack(spacing: 0) {
                hero(tracks)
                ForEach(Array(tracks.enumerated()), id: \.element.uniqueId) { position, track in
                    let current = player.current?.uniqueId == track.uniqueId
                    PlaylistTrackRow(
                        track: track,
                        tracks: tracks,
                        index: position,
                        query: query,
                        isCurrent: current,
                        isPlaying: current && player.isPlaying,
                        isFavorite: library.isFavorite(track.uniqueId),
                        lists: library.playlists,
                        player: player,
                        library: library
                    ) {
                        library.removeTrack(uniqueId: track.uniqueId, from: playlistId)
                    }

                    if position + 1 < tracks.count {
                        rowRule
                    }
                }
                if tracks.isEmpty {
                    emptyNote
                }
            }
            .padding(.bottom, MusicPlaylistMetrics.detailBottom)
        }
        .scrollIndicators(.hidden)
    }

    @ToolbarContentBuilder
    private var barMenu: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button {
                    renaming = true
                } label: {
                    Label("Đổi tên", systemImage: "pencil")
                }
                Button {
                    choosingCover = true
                } label: {
                    Label("Đổi ảnh bìa", systemImage: "photo.on.rectangle")
                }
                if playlist?.coverPath != nil {
                    Button("Gỡ ảnh bìa") {
                        library.clearCover(playlistId: playlistId)
                    }
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

    /// Everything this screen can put over itself: the photo picker for a new cover, the sheet that
    /// renames, and the two questions it asks before it destroys anything.
    @ViewBuilder
    private func presentations<Content: View>(_ content: Content) -> some View {
        content
            .photosPicker(isPresented: $choosingCover, selection: $coverChoice, matching: .images)
            .onChange(of: coverChoice) { _, picked in
                guard let picked else { return }
                coverChoice = nil
                Task {
                    guard let data = try? await picked.loadTransferable(type: Data.self) else {
                        coverFailed = true
                        return
                    }
                    // `setCover` republishes the lists, and a new cover is a new path, so the row and
                    // the hero both re-read it from the row they are given. Nothing has to be told.
                    let written = await library.setCover(data, for: playlistId)
                    coverFailed = !written
                }
            }
            .alert("Không đọc được ảnh này", isPresented: $coverFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Danh sách vẫn giữ ảnh bìa cũ.")
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

    private var playlist: StoredPlaylist? {
        library.playlists.first { $0.id == playlistId }
    }

    private var name: String {
        playlist?.name ?? ""
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

    /// The cover the colours come from, in the order the list can offer one: the picture chosen for
    /// it, then the biggest one its first song has.
    private var paletteSource: UIImage? {
        if let path = playlist?.coverPath { return artwork.image(at: path) }
        if let cover { return artwork.largest(for: cover) }
        return nil
    }

    /// The picture, named. A chosen cover is a new file every time it is picked and a list whose
    /// first song changed is a different cover, so a key that changes when either does is enough —
    /// nothing here has to be invalidated.
    private var paletteKey: String {
        if let path = playlist?.coverPath { return "cover-\(path)" }
        return "track-\(playlistId)-\(cover?.uniqueId ?? "none")"
    }

    /// What the screen is wearing: the read this cover gave, whether it is held as state or still
    /// only in the cache, and the flat grey the reference falls back to when there is nothing to
    /// read (`PlaylistDetailView.swift:293-300`).
    private var resolved: ArtworkDetailAssets {
        assets
            ?? ArtworkPaletteProvider.cached(forKey: paletteKey)
            ?? .fallback(prefersDarkAppearance: systemColorScheme == .dark)
    }

    /// The reference's own order: read, wait out the navigation transition, then change the colours
    /// once, so a palette never swaps under a zoom still in flight
    /// (`PlaylistDetailView.swift:191-215`).
    private func readPalette() async {
        let settle = Task {
            try await Task.sleep(for: MusicScreenMotion.settle)
        }
        defer { settle.cancel() }

        let loaded = await ArtworkPaletteProvider.shared.assets(
            from: paletteSource?.cgImage,
            key: paletteKey,
            fallbackPrefersDarkAppearance: systemColorScheme == .dark
        )
        guard !Task.isCancelled, !drawn(loaded) else { return }
        do {
            try await settle.value
        } catch {
            return
        }
        withAnimation(accessibilityReduceMotion ? nil : MusicScreenMotion.paletteFade) {
            assets = loaded
        }
    }

    /// Whether the screen already shows what was just read. The backdrop counts only once it has
    /// actually been drawn, which is the reference's test and the reason a cover arriving late still
    /// fades in (`PlaylistDetailView.swift:200-205`).
    private func drawn(_ loaded: ArtworkDetailAssets) -> Bool {
        let current = resolved
        return current.palette == loaded.palette
            && (current.blurredBackdrop != nil || loaded.blurredBackdrop == nil)
    }

    /// What a list with nothing in it says. The reference uses the system's own unavailable view for
    /// this and gives it 180 pt of height (`PlaylistTrackList.swift:13-15`); the sentence under it is
    /// Doni's, because a Telegram list only fills when a song is added to one.
    private var emptyNote: some View {
        ContentUnavailableView(
            "Chưa có bài nào",
            systemImage: "music.note.list",
            description: Text("Nhấn giữ một bài trong Thư viện rồi chọn một danh sách.")
        )
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    /// The rule between rows, inset to where the words begin (`PlaylistTrackList.swift:31-39`).
    private var rowRule: some View {
        Divider()
            .overlay(Color.primary.opacity(MusicPlaylistMetrics.listDividerInk))
            .padding(.leading, MusicPlaylistMetrics.listDividerInset)
            .padding(.trailing, MusicPlaylistMetrics.listDividerTrailing)
    }

    /// The hero: cover, name, count, and the row that plays them
    /// (`PlaylistDetailContent.swift:188-227`).
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
            PlaylistArt(listId: playlistId, coverPath: playlist?.coverPath, cover: cover,
                        side: proxy.size.width,
                        radius: MusicPlaylistMetrics.heroArtRadius, artwork: artwork)
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

/// What a palette read is keyed on: the cover, and the artwork cache's own tick, because a cover
/// that arrives after the screen opened is a different picture under the same name.
private struct PaletteRead: Equatable {
    let key: String
    let revision: Int
}

/// The screen's background, transcribed from `MusicCollectionArtworkBackdrop`
/// (`PlaylistDetailContent.swift:442-487`): the palette's own colour, the cover blurred into it at
/// 0.22, and a wash that keeps the words legible — light or dark with the palette, and clipped to
/// the screen so a scaled-to-fill cover cannot push anything past it.
private struct MusicCollectionArtworkBackdrop: View {
    let blurredArtwork: CGImage?
    let palette: ArtworkDetailPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                palette.backgroundColor

                if let blurredArtwork {
                    Image(decorative: blurredArtwork, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(MusicArtworkPalette.backdropOpacity)
                        .transition(.opacity)
                }

                LinearGradient(colors: wash, startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var wash: [Color] {
        let stops = palette.prefersDarkAppearance
            ? MusicArtworkPalette.darkWash
            : MusicArtworkPalette.lightWash
        let ink: Color = palette.prefersDarkAppearance ? .black : .white
        return stops.map { ink.opacity($0) }
    }
}

/// A song in a list, the way the reference lists one: the number it sits at, its name on its own,
/// and the menu that answers for it. A playlist's rows carry no artwork column — the reference
/// gives that only to its toplist layout (`PlaylistTrackList.swift:86-284`).
private struct PlaylistTrackRow: View {
    let track: StoreTrack
    /// The list the row belongs to, which is the queue a tap hands the player.
    let tracks: [StoreTrack]
    let index: Int
    let query: String
    let isCurrent: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    /// The lists this song could also join. They are laid out flat rather than in a submenu: a
    /// menu inside a menu is the one shape this app cannot check renders, having never been run in
    /// a simulator.
    let lists: [StoredPlaylist]
    let player: Player
    let library: Library
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: MusicPlaylistMetrics.listRowOuterGap) {
            Button(action: playOrPause) {
                HStack(spacing: MusicPlaylistMetrics.listRowGap) {
                    leading

                    VStack(alignment: .leading, spacing: MusicPlaylistMetrics.listRowTextGap) {
                        HighlightedText(text: track.displayTitle, query: query, font: .body,
                                        color: .primary, accent: MusicTint.accent)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // The reference's own slot here says whether a song is on the device; this app has the
            // same thing to say, and it says it with the same glyph at the same size.
            if !track.isDownloaded {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button {
                    player.playNext(track)
                } label: {
                    Label("Phát tiếp theo",
                          systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button {
                    library.toggleFavorite(track)
                } label: {
                    Label(isFavorite ? "Bỏ yêu thích" : "Yêu thích",
                          systemImage: isFavorite ? "heart.slash" : "heart")
                }
                Divider()
                ForEach(lists) { list in
                    Button("Thêm vào “\(list.name)”") {
                        library.add(track, to: list.id)
                    }
                }
                Divider()
                Button(role: .destructive, action: onRemove) {
                    Label("Bỏ khỏi danh sách", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: MusicPlaylistMetrics.listMenuWidth,
                           height: MusicPlaylistMetrics.listMenuHeight)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Thêm cho “\(track.displayTitle)”")
        }
        .padding(.leading, MusicPlaylistMetrics.trackRowLeading)
        .padding(.trailing, MusicPlaylistMetrics.trackRowTrailing)
        .padding(.vertical, MusicPlaylistMetrics.trackRowVertical)
        .background(isCurrent
            ? Color.primary.opacity(MusicPlaylistMetrics.listRowCurrent)
            : Color.clear)
        .accessibilityElement(children: .contain)
    }

    /// The number, or — on the row the player is holding — the 32 pt ring that shows which way the
    /// triangle is pointing (`:251-284`).
    @ViewBuilder
    private var leading: some View {
        if isCurrent {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(MusicPlaylistMetrics.listMarkInk),
                            lineWidth: MusicPlaylistMetrics.listMarkStroke)

                if player.isFetchingFile {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.bold))
                }
            }
            .frame(width: MusicPlaylistMetrics.listMarkCircle,
                   height: MusicPlaylistMetrics.listMarkCircle)
            .frame(width: MusicPlaylistMetrics.listIndexColumn)
        } else {
            Text((index + 1).formatted())
                .font(.title3)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: MusicPlaylistMetrics.listIndexColumn, alignment: .center)
        }
    }

    /// Tapping the row the player already holds pauses it; any other row becomes the queue's head.
    private func playOrPause() {
        if isCurrent {
            player.toggle()
        } else {
            player.play(track, in: tracks.map { $0 as any Playable })
        }
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

    /// The scheme the screen was opened with, which on this surface is the cover's, not the phone's
    /// (`:325`, `:403-409`).
    @Environment(\.colorScheme) private var colorScheme

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
                .tint(colorScheme == .dark ? .white : .black)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
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
