import SwiftUI
import Support
import TelegramDesignSystem

/// The reference's shelf: a 17pt semibold title on the same baseline as a "see all" affordance, then a
/// grid of cards that decides its own column count (`DesktopHomeView.swift:16-44`,
/// `GridItem(.adaptive(minimum: 145, maximum: 205), spacing: 24)`).
struct DesktopShelf<Content: View>: View {
    let title: String
    var showsSeeAll = false
    var seeAll: () -> Void = {}
    @ViewBuilder var content: () -> Content

    private static var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 145, maximum: 205), spacing: 24)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                if showsSeeAll {
                    Button("Xem tất cả", action: seeAll)
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
            }
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 20) {
                content()
            }
        }
    }
}

/// Home, on the reference's screens: the shelves the library can actually fill, in the order a listener
/// reaches for them — what was just playing, then the lists they made, then the channels.
struct DesktopHomePane: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Player

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Trang chủ")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    if !songs.isEmpty {
                        Button {
                            player.play(songs[0], in: songs)
                        } label: {
                            Label("Phát tất cả", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MusicTint.accent)
                        .controlSize(.large)
                    }
                }

                if library.channels.isEmpty {
                    ContentUnavailableView {
                        Label("Chưa có kênh nào", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("Doni lấy nhạc từ các kênh Telegram bạn thêm vào.")
                    } actions: {
                        Button(action: openChannels) { Text("Thêm kênh") }
                            .buttonStyle(.borderedProminent)
                            .tint(MusicTint.accent)
                    }
                    .padding(.top, 60)
                } else {
                    DesktopHomeHeroes()

                    if !recent.isEmpty {
                        DesktopShelf(title: "Nghe tiếp") {
                            ForEach(recent, id: \.uniqueId) { track in
                                DesktopMediaCard(
                                    title: track.displayTitle,
                                    subtitle: track.displayPerformer,
                                    artwork: .track(track)
                                ) {
                                    player.play(track, in: recent)
                                }
                            }
                        }
                    }

                    if !library.playlists.isEmpty {
                        DesktopShelf(title: "Danh sách của bạn",
                                     showsSeeAll: library.playlists.count > 6,
                                     seeAll: selectPlaylists) {
                            ForEach(library.playlists.prefix(6)) { list in
                                DesktopMediaCard(
                                    title: list.name,
                                    subtitle: localized("%@ bài", list.trackCount.formatted()),
                                    artwork: library.cardArtwork(for: list)
                                ) {
                                    model.ui.navigate(to: .playlist(list.id))
                                } playAction: {
                                    let tracks = DesktopPanes.playlist(model, id: list.id)
                                    if let first = tracks.first {
                                        player.play(first, in: tracks)
                                    }
                                }
                            }
                        }
                    }

                    DesktopShelf(title: "Kênh",
                                 showsSeeAll: library.channels.count > 6,
                                 seeAll: selectChannels) {
                        ForEach(library.channels.prefix(6)) { channel in
                            DesktopMediaCard(
                                title: channel.title,
                                subtitle: nil,
                                artwork: .image(cover(channel.avatarPath))
                            ) {
                                model.ui.navigate(to: .channel(chatId: channel.chatId,
                                                               title: channel.title))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .navigationTitle("Trang chủ")
    }

    private var songs: [any Playable] { DesktopPanes.all(model) }
    private var recent: [any Playable] { DesktopPanes.recent(model) }

    private func cover(_ path: String?) -> DoniImage? {
        guard let path, let image = CoverArtwork.shared.image(at: path) else { return nil }
        return image
    }

    private func openChannels() { model.ui.selection = .channels }
    private func selectChannels() { model.ui.selection = .channels }
    private func selectPlaylists() { model.ui.selection = .playlists }
}

/// The lists the listener made, as cards — the reference's `DesktopLibraryView(section: .playlists)` is
/// a grid of the same.
struct DesktopPlaylistsPane: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    @State private var showsCreation = false
    @State private var name = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Danh sách")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    Button {
                        name = ""
                        showsCreation = true
                    } label: {
                        Label("Danh sách mới", systemImage: "plus")
                    }
                    .controlSize(.large)
                }

                if library.playlists.isEmpty {
                    ContentUnavailableView("Chưa có danh sách nào",
                                           systemImage: "music.note.list",
                                           description: Text("Thêm một bài vào danh sách từ bất kỳ đâu."))
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 205), spacing: 24)],
                              alignment: .leading,
                              spacing: 20) {
                        ForEach(library.playlists) { list in
                            DesktopMediaCard(
                                title: list.name,
                                subtitle: localized("%@ bài", list.trackCount.formatted()),
                                artwork: library.cardArtwork(for: list)
                            ) {
                                model.ui.navigate(to: .playlist(list.id))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .navigationTitle("Danh sách")
        .sheet(isPresented: $showsCreation) {
            DesktopNameSheet(title: "Danh sách mới", placeholder: "Tên danh sách", name: $name) {
                library.createPlaylist(named: name)
                showsCreation = false
            }
        }
    }

}

/// The channels, as rows rather than cards: a channel is a place, and what a listener wants from the
/// list is how much of it Doni has read and whether it is still being read.
struct DesktopChannelsPane: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var session: TelegramSession
    @State private var showsAdd = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Kênh")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    Button {
                        showsAdd = true
                    } label: {
                        Label("Thêm kênh", systemImage: "plus")
                    }
                    .controlSize(.large)
                }

                if library.channels.isEmpty {
                    ContentUnavailableView("Chưa thêm kênh nào",
                                           systemImage: "antenna.radiowaves.left.and.right",
                                           description: Text("Dán một link t.me hoặc chọn từ danh sách trò chuyện."))
                        .padding(.top, 60)
                } else {
                    // Cards, as the reference shows them (`DesktopHomeQuickActionsView`'s grid and the
                    // channel shelf): a channel is a place you go into, and its picture is the sign.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 205), spacing: 24)],
                              alignment: .leading,
                              spacing: 20) {
                        ForEach(library.channels) { channel in
                            DesktopMediaCard(
                                title: channel.title,
                                subtitle: nil,
                                artwork: .image(channel.avatarPath
                                    .flatMap { CoverArtwork.shared.image(at: $0) })
                            ) {
                                model.ui.navigate(to: .channel(chatId: channel.chatId,
                                                               title: channel.title))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .task(id: library.channels.map(\.chatId)) {
            let store = library, chats = session
            for channel in store.channels {
                await store.loadAvatar(of: channel, on: chats)
            }
        }
        .navigationTitle("Kênh")
        .sheet(isPresented: $showsAdd) {
            DesktopAddChannelSheet(session: session, library: library) {
                model.indexer.run(session, library: library)
            }
        }
    }
}

/// One channel in the list. The picture is the chat's own, at the size the phone's list uses; the second
/// line says whether Doni is still reading it, which is the one thing a channel row can be asked.
struct DesktopChannelRow: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var session: TelegramSession
    let channel: StoreChannel
    let open: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                avatar
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.045) : Color.clear,
                    in: .rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
        // Nothing else in the desktop app fetches a chat photo, so without this the row wore its
        // initial forever. The phone asks from the row itself (`UI/SettingsView.swift:554`), which is
        // where the one `getChat` and the one 160x160 JPEG belong; a channel that has no photo keeps
        // the initial, because that is what there is to show.
        .task(id: channel.chatId) {
            await library.loadAvatar(of: channel, on: session)
        }
    }

    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MusicTint.accent.opacity(0.18))
            if let image = library.avatarImage(of: channel) {
                Image(doni: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text(String(channel.title.first.map(Character.init) ?? "?").uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MusicTint.accent)
            }
        }
    }

    private var subtitle: String {
        let songs = DesktopPanes.channel(model, chatId: channel.chatId).count
        if model.indexer.isReading {
            return localized("%@ bài · đang đọc", songs.formatted())
        }
        return localized("%@ bài", songs.formatted())
    }
}

/// A playlist opened from a card. The pane's own header carries the two verbs, as it does everywhere
/// else — a tab's toolbar puts a primary action at the top of the window, far from the list it acts on.
/// A playlist opened from the list — the reference's collection page, not a list with a title.
///
/// `DesktopRouteView.swift:65-131`: a 278 pt cover at radius 11 with the metadata column beside it on
/// the bottom baseline, 34 pt between them and capped at 620 pt wide; the eyebrow at 11 semibold
/// secondary, the name at 32 bold over two lines, the source line at 22 semibold in red, the counts at
/// 13 medium secondary, then the buttons 10 pt under them. `DesktopPlaylistDetailView.swift:34-58`:
/// header, 34 pt, divider, 34 pt, rows — with 42 pt on the sides and 34 above and below, and the rows
/// drawn without covers because in a list the song is the thing, not its picture.
struct DesktopPlaylistDetail: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var artwork: CoverArtwork
    @EnvironmentObject private var session: TelegramSession

    let id: Int64

    @State private var renaming = false
    @State private var newName = ""
    @State private var isCoverHovered = false

    private static let coverSide: CGFloat = 278
    private static let coverRadius: CGFloat = 11

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                Divider()
                if tracks.isEmpty { empty } else { rows }
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 34)
        }
        .navigationTitle(Text(name))
        .task(id: Array(tracks.prefix(40).map(\.uniqueId))) {
            artwork.prefetch(Array(tracks.prefix(40)), via: session.covers(), side: 42)
        }
        .alert("Danh sách mới", isPresented: $renaming) {
            TextField("Tên danh sách", text: $newName)
            Button("Lưu") {
                guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                library.renamePlaylist(id: id, name: newName)
            }
            Button("Huỷ", role: .cancel) {}
        }
    }

    private var playlist: StoredPlaylist? {
        library.playlists.first { $0.id == id }
    }

    private var tracks: [any Playable] {
        library.tracks(in: id)
    }

    private var name: String {
        playlist?.name ?? localized("Danh sách")
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 34) {
            cover
            details
            Spacer(minLength: 0)
        }
    }

    /// The list's own picture when the listener chose one; otherwise its first song's, which is the
    /// phone's rule for a playlist cover and the only honest fallback.
    @ViewBuilder private var cover: some View {
        ZStack {
            if let path = playlist?.coverPath, let image = CoverArtwork.shared.image(at: path) {
                Image(doni: image)
                    .resizable()
                    .scaledToFill()
            } else if let first = library.firstTrack(in: id) {
                DesktopArtworkView(track: first, side: Self.coverSide,
                                   cornerRadius: Self.coverRadius)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Self.coverRadius, style: .continuous)
                        .fill(MusicTint.accent.opacity(0.14))
                    Image(systemName: "music.note.list")
                        .font(.system(size: 92, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(MusicTint.accent)
                }
            }
        }
        .frame(width: Self.coverSide, height: Self.coverSide)
        .clipShape(.rect(cornerRadius: Self.coverRadius, style: .continuous))
        .scaleEffect(isCoverHovered ? 1.012 : 1)
        .shadow(color: .black.opacity(isCoverHovered ? 0.24 : 0.20),
                radius: isCoverHovered ? 22 : 18, y: isCoverHovered ? 12 : 10)
        .onHover { isCoverHovered = $0 }
        .animation(.snappy(duration: 0.25, extraBounce: 0.04), value: isCoverHovered)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Danh sách phát"))
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text(name)
                .font(.system(size: 32, weight: .bold))
                .lineLimit(2)

            if let singer = firstSinger {
                Text(singer)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MusicTint.accent)
                    .lineLimit(2)
            }

            Text(metadata)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            actions
                .padding(.top, 10)
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(.bottom, 6)
    }

    /// The reference's red line is the playlist's owner. Doni has no owner field, and the one thing in
    /// the same position that is true of the music is who is singing the first song.
    private var firstSinger: String? {
        guard let first = tracks.first, !first.displayPerformer.isEmpty else { return nil }
        return first.displayPerformer
    }

    private var metadata: String {
        let seconds = tracks.reduce(0) { $0 + ($1.duration ?? 0) }
        return localized("%1$@ bài · %2$@",
                         tracks.count.formatted(),
                         MediaClock.duration(seconds) ?? "0:00")
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                guard let first = tracks.first else { return }
                player.play(first, in: tracks)
            } label: {
                Label("Phát tất cả", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(MusicTint.accent)

            Button {
                guard let first = tracks.first else { return }
                player.setShuffled(true)
                player.play(first, in: tracks)
            } label: {
                Label("Phát ngẫu nhiên", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)

            Menu {
                Button("Đổi tên…", systemImage: "pencil") {
                    newName = name
                    renaming = true
                }
                Divider()
                Button("Xoá danh sách", systemImage: "trash", role: .destructive) {
                    library.deletePlaylist(id: id)
                    model.ui.path.removeAll()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .controlSize(.large)
    }

    /// Which channel a song of the list was posted in. The list itself has no source: its songs come
    /// from wherever they were kept.
    private func channelTitle(for track: any Playable) -> String? {
        library.channels.first { $0.chatId == track.chatId }?.title
    }

    private var rows: some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(tracks.enumerated()), id: \.element.uniqueId) { offset, track in
                DesktopTrackRow(
                    track: track,
                    index: offset,
                    tracks: tracks,
                    showsArtwork: false,
                    source: channelTitle(for: track),
                    onRemove: { library.removeTrack(uniqueId: $0.uniqueId, from: id) }
                )
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Danh sách trống", systemImage: "music.note.list")
        } description: {
            Text("Thêm một bài từ bất kỳ danh sách nào bằng dấu ⋯ cạnh bài đó.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// A channel opened from the list — the same pane, with the songs that channel posted.
struct DesktopChannelDetail: View {
    @Environment(DesktopAppModel.self) private var model
    let chatId: Int64
    let title: String

    var body: some View {
        DesktopTrackPane(title: title, tracks: DesktopPanes.channel(model, chatId: chatId))
    }
}

/// One text field and one verb, for the two things the desktop asks a name for. The phone has the same
/// sheet; a Mac's is a card that closes on Escape.
struct DesktopNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    @Binding var name: String
    let submit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 15, weight: .semibold))
            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit(submit)
            HStack {
                Button("Huỷ") { dismiss() }
                Button("Tạo", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

extension Library {
    /// The phone's rule, kept: the picture the listener chose, else the first song's cover, else the
    /// list glyph. A Telegram list has no artwork of its own — its songs do, and the first one is what
    /// the list sounds like.
    func cardArtwork(for list: StoredPlaylist) -> DesktopCardArtwork {
        if let path = list.coverPath, let image = CoverArtwork.shared.image(at: path) {
            return .image(image)
        }
        if let first = firstTrack(in: list.id) {
            return .track(first)
        }
        return .glyph("music.note.list")
    }
}
