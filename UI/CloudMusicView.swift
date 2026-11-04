import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The tab MeloX puts its cloud drive in (`Features/Cloud/CloudMusicView.swift:99-206`), wearing
/// Doni's own meaning: the songs Telegram has indexed that are **not on this phone yet**.
///
/// The reference's cloud is a NetEase drive — files on someone else's server, listed with the same
/// plain rows as its local library, with a quota over the top and a device-side copy made by
/// tapping. Doni has the same split already: TDLib knows a thousand songs in the channel and holds
/// none of them until asked. Same list, same gesture, one difference worth naming — the transfer runs
/// the other way. Nothing here is uploaded anywhere; a row is a file on Telegram's servers that this
/// app is being offered the chance to bring home.
///
/// So the reference's upload button becomes the button that adds a channel, its quota line becomes
/// how much of the phone the library has already taken, and its destructive swipe becomes a download:
/// a row this app cannot delete, because the next walk would re-index the song and the list would be
/// lying about what it removed.
struct CloudMusicView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    @ObservedObject var indexer: LibraryIndexer

    @State private var query = ""
    @State private var showsAddChannel = false
    /// The rows this screen has asked TDLib for and is still waiting on, in the order they were
    /// pressed. MeloX holds the same idea as one `isUploading` flag on its store
    /// (`CloudMusicView.swift:110-115`); here the wait is per row, so the row that landed can leave
    /// while the others keep their spinner.
    @State private var fetching: [String] = []

    var body: some View {
        List {
            // The reference's progress row, at the head of the list rather than inside a row, so a
            // swipe that is still running stays visible while the list scrolls under it.
            if !fetching.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(waitingLine)
                        .foregroundStyle(.secondary)
                }
            }

            if !visible.isEmpty {
                Section {
                    Button(action: playAll) {
                        HStack {
                            Label("Phát tất cả", systemImage: "play.fill")
                            Spacer()
                        }
                    }
                } header: {
                    Text(headline)
                }

                ForEach(visible) { track in
                    Button {
                        player.play(track, in: visible.map { $0 as any Playable })
                    } label: {
                        MusicTrackRow(track: track, artwork: artwork)
                    }
                    .buttonStyle(.plain)
                    .task(id: track.uniqueId) {
                        await artwork.load(track: track, via: session.covers(),
                                           side: MusicSearchMetrics.songArt)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            download(track)
                        } label: {
                            Label("Tải về máy", systemImage: "arrow.down.circle")
                        }
                        .tint(MusicTint.accent)
                    }
                }
            }

            footer
        }
        .listStyle(.plain)
        .navigationTitle("Cloud Music")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm bài chưa tải")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showsAddChannel = true
                } label: {
                    Label("Thêm kênh nhạc", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .refreshable { await indexer.reload(session, library: library) }
        .overlay {
            if visible.isEmpty && !indexer.isReading {
                emptyState
            }
        }
        .sheet(isPresented: $showsAddChannel) {
            AddChannelSheet(session: session, library: library) {
                indexer.run(session, library: library)
            }
        }
    }

    // MARK: What the list is

    /// Every indexed song the phone does not hold, newest first — the order `Library` reads its
    /// track table in, and the same order the home feed's shelves use.
    private var pending: [StoreTrack] {
        library.storedTracks.filter { !$0.isDownloaded }
    }

    /// The same fold the favourites and playlist screens use, so "tinh yeu" still finds "Tình yêu"
    /// while the field is only being asked about this list.
    private var visible: [StoreTrack] {
        let key = SearchTextFold.normalized(query)
        guard !key.isEmpty else { return pending }
        return pending.filter {
            SearchTextFold.normalized(
                "\($0.displayTitle) \($0.displayPerformer) \($0.fileName)"
            ).contains(key)
        }
    }

    /// The line over the list. The reference's is its drive quota; the number this app can say in
    /// the same slot is how much of the catalogue is still out on Telegram, and what the phone has
    /// already spent on the rest.
    private var headline: String {
        if !query.isEmpty {
            return "\(visible.count.formatted()) kết quả"
        }
        return "\(pending.count.formatted()) bài chưa tải · "
            + "\(DataSize.string(library.downloadedBytes)) trên máy"
    }

    private var waitingLine: String {
        fetching.count == 1
            ? "Đang tải 1 bài về máy…"
            : "Đang tải \(fetching.count.formatted()) bài về máy…"
    }

    // MARK: Foot and empty

    /// MeloX's pagination footer (`CloudMusicView.swift:216-248`): a centred line of `subheadline`
    /// over a hidden separator while it is still working, and a `bordered` retry button when the
    /// read broke. A walk is what makes new rows appear here, so this is the list's version of
    /// "loading more".
    @ViewBuilder
    private var footer: some View {
        if indexer.isReading {
            HStack {
                Spacer()
                ProgressView(indexer.statusLine.isEmpty ? "Đang đọc kênh…" : indexer.statusLine)
                Spacer()
            }
        } else if let failure = indexer.failureLine {
            VStack(spacing: 8) {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Đọc lại kênh") { indexer.run(session, library: library) }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .listRowSeparator(.hidden)
        }
    }

    /// The three empties this screen can be, in the reference's own shape
    /// (`CloudMusicView.swift:178-199`): a search with no answer, a library nothing has been read
    /// into, and a phone that already holds everything.
    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if library.channels.isEmpty {
            ContentUnavailableView {
                Label("Chưa có kênh nhạc nào", systemImage: "icloud")
            } description: {
                Text("Thêm một kênh Telegram để Doni biết trong đó có bài nào.")
            } actions: {
                Button("Thêm kênh nhạc") { showsAddChannel = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if pending.isEmpty {
            ContentUnavailableView {
                Label("Mọi bài đã có trên máy", systemImage: "checkmark.icloud")
            } description: {
                Text("\(library.trackCount.formatted()) bài trong kênh đã nằm trong "
                    + "\(DataSize.string(library.downloadedBytes)) bạn đang giữ.")
            } actions: {
                Button("Đọc lại kênh") { indexer.run(session, library: library) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("Chưa có bài nào trong kênh", systemImage: "icloud")
            } description: {
                Text("Kênh trên danh sách chưa có file nhạc nào được đọc.")
            } actions: {
                Button("Đọc lại kênh") { indexer.run(session, library: library) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private func playAll() {
        guard let first = visible.first else { return }
        player.play(first, in: visible.map { $0 as any Playable })
    }

    /// One swipe, one file. The row stops being a cloud row when the path lands — `Library` patches
    /// the published row in place — so this list drains as its downloads finish.
    private func download(_ track: StoreTrack) {
        guard !fetching.contains(track.uniqueId) else { return }
        fetching.append(track.uniqueId)
        Task {
            await player.download(track)
            fetching.removeAll { $0 == track.uniqueId }
        }
    }
}

#Preview {
    NavigationStack {
        CloudMusicView(
            session: TelegramSession(),
            player: Player(),
            artwork: CoverArtwork.shared,
            library: Library.shared,
            indexer: LibraryIndexer()
        )
    }
}
