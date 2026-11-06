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
                                    artwork: .image(cover(list.coverPath))
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
                                artwork: .image(cover(list.coverPath))
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

    private func cover(_ path: String?) -> DoniImage? {
        guard let path else { return nil }
        return CoverArtwork.shared.image(at: path)
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
                    LazyVStack(spacing: 2) {
                        ForEach(library.channels) { channel in
                            DesktopChannelRow(channel: channel) {
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
    }

    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MusicTint.accent.opacity(0.18))
            if let path = channel.avatarPath, let image = CoverArtwork.shared.image(at: path) {
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
struct DesktopPlaylistDetail: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    let id: Int64

    var body: some View {
        DesktopTrackPane(
            title: name,
            tracks: DesktopPanes.playlist(model, id: id),
            emptyPrompt: localized("Danh sách trống"),
            onRemove: { library.removeTrack(uniqueId: $0.uniqueId, from: id) }
        )
    }

    private var name: String {
        library.playlists.first { $0.id == id }?.name ?? localized("Danh sách")
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
