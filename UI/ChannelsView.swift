import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The channels: where the music comes from, shown as places rather than as rows.
///
/// The reference draws a channel as a card — its picture over the square, its name under it
/// (`DesktopHomeQuickActionsView.swift:271-375` on the desktop, the shelf grids on the phone) — and
/// that is the honest shape: a channel is a door you go through, not a line in a table. The picture is
/// the chat's own, fetched once per channel the first time it is looked at
/// (`Library.loadAvatar`, `td_api.tl:4080` — `chat.photo.small` is a 160×160 JPEG).
struct ChannelsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var showsAdd = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if library.channels.isEmpty {
                    empty
                } else {
                    grid
                }
            }
            .padding(.horizontal, MusicExploreMetrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .navigationTitle("Kênh")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Thêm kênh")
            }
        }
        // Chat ids route this stack; the tab's own list is the only thing that pushes them.
        .navigationDestination(for: Int64.self) { chatId in
            ChannelSongsView(session: session, indexer: indexer, player: player,
                             artwork: artwork, library: library, chatId: chatId)
        }
        .sheet(isPresented: $showsAdd) {
            AddChannelSheet(session: session, library: library) {
                indexer.run(session, library: library)
            }
        }
        .task(id: library.channels.map(\.chatId)) {
            let store = library, chats = session
            for channel in store.channels {
                await store.loadAvatar(of: channel, on: chats)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200),
                                     spacing: 12)],
                  alignment: .leading,
                  spacing: 20) {
            ForEach(library.channels) { channel in
                NavigationLink(value: channel.chatId) {
                    ChannelCard(channel: channel, library: library)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Chưa thêm kênh nào", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text("Dán một link t.me hoặc chọn từ danh sách trò chuyện.")
        } actions: {
            Button("Thêm kênh") { showsAdd = true }
                .buttonStyle(.borderedProminent)
                .tint(MusicTint.accent)
        }
        .padding(.top, 60)
    }
}

/// One channel: its picture over a square, its name under it in two lines.
private struct ChannelCard: View {
    let channel: StoreChannel
    @ObservedObject var library: Library

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(MusicArtworkMetrics.placeholderFill))

                if let image = library.avatarImage(of: channel) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(channel.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(localized("%@ bài", library.store.trackCount(chatId: channel.chatId).formatted()))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// What one channel posted, newest first, with the two verbs a collection has.
struct ChannelSongsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    let chatId: Int64

    var body: some View {
        List {
            if !songs.isEmpty {
                Button(action: playAll) {
                    HStack {
                        Label("Phát tất cả", systemImage: "play.fill")
                        Spacer()
                    }
                }
            }
            ForEach(songs, id: \.uniqueId) { track in
                Button {
                    player.play(track, in: songs)
                } label: {
                    MusicTrackRow(track: track, secondary: track.displayPerformer,
                                  artwork: artwork)
                        .task(id: track.uniqueId) {
                            await artwork.load(track: track, via: session.covers(),
                                               side: MusicSearchMetrics.songArt)
                        }
                }
                .buttonStyle(.plain)
                .trackActions(track, library: library) {}
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: shuffle) {
                    Image(systemName: "shuffle")
                }
                .accessibilityLabel("Phát ngẫu nhiên")
            }
        }
    }

    /// The walk's list, filtered by chat. `Library.tracks(in:)` takes a *playlist* id, and handing it a
    /// chat id is how a channel with two hundred songs opened empty.
    private var songs: [any Playable] {
        indexer.tracks.filter { $0.chatId == chatId }
    }

    private var title: String {
        library.channels.first { $0.chatId == chatId }?.title ?? localized("Kênh")
    }

    private func playAll() {
        guard let first = songs.first else { return }
        player.play(first, in: songs)
    }

    private func shuffle() {
        guard let first = songs.first else { return }
        player.setShuffled(true)
        player.play(first, in: songs)
    }
}
