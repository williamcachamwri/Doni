import SwiftUI
import Support
import TelegramDesignSystem
import UniformTypeIdentifiers

/// The tab MeloX puts its cloud drive in (`Features/Cloud/CloudMusicView.swift:99-206`), meaning the
/// same thing here: **the files the user brought themselves**.
///
/// The reference's cloud is a NetEase drive — songs that live on someone else's server, listed with
/// the same plain rows as its local library, with a quota over the top and a device-side copy made by
/// tapping. Doni's is the mirror of that and the copy is the point: a song here was picked out of the
/// Files app, copied into this app's own storage, and is on the phone until the user deletes it.
/// Nothing is uploaded anywhere. The upload glyph therefore stays an upload — into the library, not
/// out of the phone — and the destructive swipe is the one the reference can honestly make, because
/// the row that goes here is gone for good rather than re-listed by the next page of a server query.
///
/// What the indexed-but-not-downloaded songs of a Telegram channel are for moved to
/// `PendingSongsView`, which is the downloads screen this list used to be.
struct CloudMusicView: View {
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var query = ""
    @State private var showsFileImporter = false
    /// The files this screen is holding open. MeloX has one `isUploading` flag on its store
    /// (`CloudMusicView.swift:110-115`); a picker here can hand over several at once, so the count is
    /// what says "still working" and how many are left.
    @State private var importing = 0
    /// The song a swipe asked to delete, held until the dialog answers. MeloX's `pendingDeletion`
    /// (`CloudMusicView.swift:51-71`), same shape: the row names itself in the button so a tap that
    /// was meant for the row above it cannot take the wrong file.
    @State private var pendingDeletion: StoreTrack?
    /// The one failure this screen can produce: the file would not open, or would not copy. MeloX's
    /// error alert (`CloudMusicView.swift:72-86`), for the same reason — a picker that seemed to work
    /// and added nothing is a silent bug unless it says so.
    @State private var failure: String?

    var body: some View {
        List {
            if importing > 0 {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(waitingLine)
                        .foregroundStyle(.secondary)
                }
            }

            if !visible.isEmpty {
                Section {
                    Button(action: playAll) {
                        Label(query.isEmpty ? "Phát tất cả" : "Phát kết quả",
                              systemImage: "play.fill")
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
                        // No downloader: the cover of a file the phone owns is read out of the file,
                        // which is the first thing `CoverArtwork` tries and the only thing it needs.
                        await artwork.load(track: track, side: MusicSearchMetrics.songArt)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = track
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Cloud Music")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm bài của bạn")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsFileImporter = true
                } label: {
                    if importing > 0 {
                        ProgressView()
                    } else {
                        Label("Thêm nhạc từ file", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                }
                .disabled(importing > 0)
                .accessibilityLabel(importing > 0 ? "Đang thêm nhạc…" : "Thêm nhạc từ file")
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                failure = error.localizedDescription
            }
        }
        .confirmationDialog("Xoá bài này?", isPresented: deleting,
                           titleVisibility: .visible, presenting: pendingDeletion) { song in
            Button("Xoá \(song.displayTitle)", role: .destructive) {
                library.removeLocal(song)
                pendingDeletion = nil
            }
            Button("Huỷ", role: .cancel) {}
        } message: { _ in
            Text("Bài này sẽ mất khỏi Doni. Tệp gốc bạn đã chọn vẫn còn ở nơi nó đang nằm.")
        }
        .alert("Không thêm được bài", isPresented: failing) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "File không đọc được.")
        }
        .overlay {
            if visible.isEmpty && importing == 0 {
                emptyState
            }
        }
    }

    // MARK: What the list is

    /// The songs this app owns outright, newest first — the order `Library` reads its track table in.
    private var kept: [StoreTrack] {
        library.storedTracks.filter(\.isLocal)
    }

    /// The same fold the favourites and playlist screens use, so "tinh yeu" still finds "Tình yêu".
    private var visible: [StoreTrack] {
        let key = SearchTextFold.normalized(query)
        guard !key.isEmpty else { return kept }
        return kept.filter {
            SearchTextFold.normalized(
                "\($0.displayTitle) \($0.displayPerformer) \($0.fileName)"
            ).contains(key)
        }
    }

    /// The reference's quota line, in the same slot (`CloudMusicView.swift:128-136`), saying the only
    /// thing this app can: how many files the user has brought and how much of the phone they cost.
    private var headline: String {
        if !query.isEmpty {
            return "\(visible.count.formatted()) kết quả"
        }
        let bytes = kept.reduce(Int64(0)) { $0 + $1.size }
        return "\(kept.count.formatted()) bài của bạn · " + DataSize.string(bytes)
    }

    private var waitingLine: String {
        importing == 1
            ? "Đang thêm 1 bài vào thư viện…"
            : "Đang thêm \(importing.formatted()) bài vào thư viện…"
    }

    private var deleting: Binding<Bool> {
        Binding(get: { pendingDeletion != nil },
                set: { shown in if !shown { pendingDeletion = nil } })
    }

    private var failing: Binding<Bool> {
        Binding(get: { failure != nil },
                set: { shown in if !shown { failure = nil } })
    }

    // MARK: Empty

    /// The two empties, in the reference's own shape (`CloudMusicView.swift:178-199`): a search with
    /// no answer, and a drive nobody has put anything in yet — whose one action is the button that
    /// fills it.
    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView {
                Label("Chưa có bài nào của bạn", systemImage: "externaldrive")
            } description: {
                Text("Chọn một file nhạc trên máy để Doni giữ nó trong thư viện, "
                    + "nghe được cả khi không có mạng.")
            } actions: {
                Button("Thêm nhạc từ file") { showsFileImporter = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private func playAll() {
        guard let first = visible.first else { return }
        player.play(first, in: visible.map { $0 as any Playable })
    }

    /// One picker, as many files as were selected. Hashing and copying are a few hundred milliseconds
    /// of disk each, so they run one after another rather than all at once, and the count at the head
    /// of the list ticks down as they land — the only progress a user can act on.
    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        importing = urls.count
        Task {
            var added = 0
            for url in urls {
                if await library.importMusic(from: url) != nil { added += 1 }
                importing -= 1
            }
            if added == 0 { failure = "Không file nào mở được." }
        }
    }
}

#Preview {
    NavigationStack {
        CloudMusicView(player: Player(), artwork: CoverArtwork.shared, library: Library.shared)
    }
}
