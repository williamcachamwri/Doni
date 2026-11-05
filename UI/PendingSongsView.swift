import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// Songs Telegram has indexed that this phone does not hold — MeloX's downloads screen
/// (`Features/Downloads/DownloadsView.swift`, `Features/Library/LibraryDownloadsView.swift`), where the
/// transfer is a fetch rather than a queue. Reached from Settings, under the three numbers it is the
/// second half of.
struct PendingSongsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    @ObservedObject var indexer: LibraryIndexer

    @State private var query = ""
    @State private var showsAddChannel = false
    /// Row ids this screen has asked TDLib for and is still waiting on, in press order. The reference
    /// has one `isUploading` flag (`CloudMusicView.swift:110-115`); here the wait is per row, so a row
    /// that lands leaves while the others keep their spinner.
    @State private var fetching: [String] = []

    var body: some View {
        List {
            // The progress row heads the list rather than sitting inside a row, so it stays visible
            // while the list scrolls under it.
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
        .navigationTitle("Bài chưa tải")
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

    /// Every indexed song the phone does not hold, newest first — `Library`'s track-table order, same
    /// as the home feed's shelves. Imported files stay out even when their copy is missing: there is
    /// no channel to fetch them from and no `file_id` to ask with, so such a row could never leave.
    private var pending: [StoreTrack] {
        library.storedTracks.filter { !$0.isDownloaded && !$0.isLocal }
    }

    /// The same fold the favourites and playlist screens use, so "tinh yeu" still finds "Tình yêu".
    private var visible: [StoreTrack] {
        let key = SearchTextFold.normalized(query)
        guard !key.isEmpty else { return pending }
        return pending.filter {
            SearchTextFold.normalized(
                "\($0.displayTitle) \($0.displayPerformer) \($0.fileName)"
            ).contains(key)
        }
    }

    /// The reference's quota slot, filled with what this app can say: how much of the catalogue is
    /// still out on Telegram, and what the phone has spent on the rest.
    private var headline: String {
        if !query.isEmpty {
            return localized("%@ kết quả", visible.count.formatted())
        }
        return localized("%@ bài chưa tải · %@ trên máy",
            pending.count.formatted(), DataSize.string(library.downloadedBytes))
    }

    private var waitingLine: String {
        fetching.count == 1
            ? "Đang tải 1 bài về máy…"
            : localized("Đang tải %@ bài về máy…", fetching.count.formatted())
    }

    // MARK: Foot and empty

    /// MeloX's pagination footer (`CloudMusicView.swift:216-248`): a centred `subheadline` line over a
    /// hidden separator while it works, a `bordered` retry when the read broke. A walk is what fills
    /// this list, so it is the list's version of "loading more".
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

    /// The three empties, in the reference's shape (`CloudMusicView.swift:178-199`): no search answer,
    /// no channel read yet, and a phone that already holds everything.
    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if library.channels.isEmpty {
            ContentUnavailableView {
                Label("Chưa có kênh nhạc nào", systemImage: "antenna.radiowaves.left.and.right")
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
                Text(localized("%@ bài trong kênh đã nằm trong %@ bạn đang giữ.",
                    library.trackCount.formatted(), DataSize.string(library.downloadedBytes)))
            } actions: {
                Button("Đọc lại kênh") { indexer.run(session, library: library) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("Chưa có bài nào trong kênh", systemImage: "antenna.radiowaves.left.and.right")
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

    /// One swipe, one file. The row stops being pending once the path lands, because `Library` patches
    /// the published row in place — so the list drains as its downloads finish.
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
        PendingSongsView(
            session: TelegramSession(),
            player: Player(),
            artwork: CoverArtwork.shared,
            library: Library.shared,
            indexer: LibraryIndexer()
        )
    }
}
