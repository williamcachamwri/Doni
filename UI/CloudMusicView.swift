import SwiftUI
import Support
import TelegramDesignSystem
import UIKit
import UniformTypeIdentifiers

/// MeloX's cloud-drive tab (`Features/Cloud/CloudMusicView.swift:99-206`), where Doni's cloud is Saved
/// Messages: the list is that chat's history and the upload is a `sendMessage` carrying the file.
/// A song picked from Files is therefore *sent*, and the staged copy deleted once Telegram
/// has the bytes.
/// Rows older builds copied into the sandbox stay listed and playable — they are the user's music.
struct CloudMusicView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    /// The account's own chat, read and written by the same object the Now Playing menu uses, so the
    /// two surfaces agree about what is already in the cloud.
    @StateObject private var cloud = CloudMusic.shared

    @State private var query = ""
    @State private var showsFileImporter = false
    /// Files still being held open. The reference has a single `isUploading` flag
    /// (`CloudMusicView.swift:110-115`); this picker takes several at once, so it counts down.
    @State private var importing = 0
    /// The song a swipe asked to delete, held until the dialog answers (MeloX's `pendingDeletion`,
    /// `CloudMusicView.swift:51-71`): the button names the row so a mis-tap cannot take the wrong file.
    @State private var pendingDeletion: StoreTrack?
    /// "The file would not open or would not copy" (MeloX's alert, `CloudMusicView.swift:72-86`): a
    /// picker that seemed to work and added nothing has to say so.
    @State private var failure: String?
    /// Where the next picker answer goes: Telegram, or the phone only. State because the choice is made
    /// a tap before the single picker callback runs.
    @State private var picksForCloud = true

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
                        // Owned files get their cover read out of the file itself, which is the
                        // first thing `CoverArtwork` tries.
                        await artwork.load(track: track, side: MusicSearchMetrics.songArt)
                    }
                    .swipeActions(edge: .trailing) {
                        // Every row can be swiped. A Saved Messages row is a real message, so the
                        // delete says so in the dialog and goes through Telegram rather than only
                        // dropping the row — which is the difference between removing a song and
                        // hiding one.
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
        .refreshable {
            // A walk of the chat is the one thing that can prove this list still matches Telegram, so the
            // screen has to let a person ask for it: pull down, or the arrow in the bar.
            await cloud.refresh(session)
        }
        .navigationTitle("Cloud Music")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm bài của bạn")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await cloud.refresh(session) }
                } label: {
                    if cloud.isBusy {
                        ProgressView()
                    } else {
                        Label("Làm mới", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                }
                .disabled(cloud.isBusy)
                // A ternary of two literals infers `String`, not `LocalizedStringKey`, and `accessibilityLabel(String)`
// never consults the catalog: without resolving these eagerly the app ships Vietnamese to every
// language behind a green strings gate, which only checks that a row exists.
                .accessibilityLabel(cloud.isBusy ? String(localized: "Đang tải danh sách…")
                    : String(localized: "Làm mới Cloud Music"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        picksForCloud = true
                        print("cloud picker requested from toolbar")
                        showsFileImporter = true
                    } label: {
                        Label("Tải lên Cloud Music", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        picksForCloud = false
                        showsFileImporter = true
                    } label: {
                        Label("Thêm vào thư viện trên máy", systemImage: "folder.badge.plus")
                    }
                } label: {
                    if importing > 0 || cloud.isBusy {
                        ProgressView()
                    } else {
                        Label("Thêm nhạc từ file", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                }
                .disabled(importing > 0)
                .accessibilityLabel(importing > 0 ? String(localized: "Đang thêm nhạc…")
                : String(localized: "Thêm nhạc từ file"))
            }
        }
        .task {
            await cloud.refresh(session)
        }
        // A second task, because this one does not end: it is the reason a song deleted in the
        // Telegram app is off this list while the phone is still on it.
        .task {
            await cloud.watchDeletes(session)
        }
        .sheet(isPresented: $showsFileImporter) {
            AudioDocumentPicker { urls in
                picked(urls)
            } onCancel: {
                print("cloud picker cancelled")
                showsFileImporter = false
            }
        }
        .confirmationDialog("Xoá bài này?", isPresented: deleting,
                           titleVisibility: .visible, presenting: pendingDeletion) { song in
            Button(localized("Xoá %@", song.displayTitle), role: .destructive) {
                pendingDeletion = nil
                if song.isLocal {
                    library.removeLocal(song)
                } else {
                    Task { await cloud.delete(session, song) }
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: { song in
            Text(song.isLocal
                ? localized("Bài này sẽ mất khỏi Doni. Tệp gốc bạn đã chọn vẫn còn ở nơi nó đang nằm.")
                : localized("Bài này sẽ bị xoá khỏi Saved Messages trên Telegram, không chỉ khỏi Doni."))
        }
        .alert("Cloud Music", isPresented: cloudFailing) {
            Button("OK", role: .cancel) { cloud.failure = nil }
        } message: {
            Text(cloud.failure ?? "")
        }
        .alert("Không thêm được bài", isPresented: failing) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? String(localized: "File không đọc được."))
        }
        .overlay {
            if visible.isEmpty && importing == 0 && !cloud.isBusy {
                emptyState
            }
        }
    }

    // MARK: What the list is

    /// The user's own songs: Saved Messages first, then rows older builds copied into the sandbox,
    /// newest first (the order `LibraryStore` reads its track table in).
    /// `CloudMusic.distinct` keeps one entry per song, because a track is often both — the Telegram
    /// copy wins, since it plays on every device and the local file is only a cache.
    private var kept: [StoreTrack] {
        CloudMusic.distinct(cloud.songs + library.storedTracks.filter(\.isLocal))
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

    /// The reference's quota slot (`CloudMusicView.swift:128-136`): how many songs the user brought and
    /// what they cost. Cloud songs count by their size on Telegram's side, not on the phone's.
    private var headline: String {
        if !query.isEmpty {
            return localized("%@ kết quả", visible.count.formatted())
        }
        let bytes = kept.reduce(Int64(0)) { $0 + $1.size }
        return localized("%@ bài của bạn · %@", kept.count.formatted(), DataSize.string(bytes))
    }

    private var waitingLine: String {
        importing == 1
            ? "Đang thêm 1 bài vào thư viện…"
            : localized("Đang thêm %@ bài vào thư viện…", importing.formatted())
    }

    private var deleting: Binding<Bool> {
        Binding(get: { pendingDeletion != nil },
                set: { shown in if !shown { pendingDeletion = nil } })
    }

    private var cloudFailing: Binding<Bool> {
        Binding(get: { cloud.failure != nil }, set: { if !$0 { cloud.failure = nil } })
    }

    private var failing: Binding<Bool> {
        Binding(get: { failure != nil },
                set: { shown in if !shown { failure = nil } })
    }

    // MARK: Empty

    /// The reference's two empty states (`CloudMusicView.swift:178-199`): a search with no answer,
    /// and an empty drive whose one action is the add button.
    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView {
                Label("Chưa có bài nào của bạn", systemImage: "externaldrive")
            } description: {
                Text("Chọn một file nhạc trên máy để Doni giữ nó trong thư viện, nghe được cả khi không có mạng.")
            } actions: {
                Button("Thêm nhạc từ file") {
                    print("cloud picker requested from empty state")
                    showsFileImporter = true
                }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private func playAll() {
        guard let first = visible.first else { return }
        player.play(first, in: visible.map { $0 as any Playable })
    }

    /// Where a picker's answer goes. Split out of the sheet's closure, which had outgrown the
    /// type checker.
    private func picked(_ urls: [URL]) {
        print("cloud picker returned \(urls.count) urls")
        showsFileImporter = false
        if picksForCloud {
            Task { await cloud.upload(session, urls: urls) }
        } else {
            importFiles(urls)
        }
    }

    /// As many files as were selected, imported one after another — a few hundred ms of disk each —
    /// with `importing` ticking down per file.
    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        // Security-scoped access is only alive inside the callback it was handed in, so it is
        // claimed here — synchronously, on the main actor, before anything awaits. Claimed later,
        // from the task below, it answers false for every file.
        let claimed = urls.filter { $0.startAccessingSecurityScopedResource() }
        print("cloud import requested count=\(urls.count) claimed=\(claimed.count)")
        importing = urls.count
        Task {
            var added = 0
            var complaint = ""
            for url in urls {
                print("cloud importing \(url.lastPathComponent)")
                switch await library.importMusic(from: url) {
                case .success(let row):
                    print("cloud imported \(row.fileName)")
                    added += 1
                case .failure(let reason) where complaint.isEmpty:
                    // The first refusal, by name: "none of these opened" is not an answerable message.
                    complaint = "\(url.lastPathComponent) — \(reason.message)"
                    print("cloud import failed \(url.lastPathComponent): \(reason.message)")
                case .failure:
                    break
                }
                importing -= 1
            }
            claimed.forEach { $0.stopAccessingSecurityScopedResource() }
            if added == 0 {
                failure = complaint.isEmpty
                    ? "Không có file nào được chọn."
                    : localized("Không thêm được: %@.", complaint)
                print("cloud import batch added zero; failure shown")
            }
        }
    }
}

/// Files picker with `asCopy: true`, so the system copies the song into the sandbox first: the import
/// then reads a reachable file instead of a `fileImporter` URL whose scoped permission may already be
/// gone by the time a background task gets to it.
private struct AudioDocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio],
                                                    asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

#Preview {
    NavigationStack {
        CloudMusicView(session: TelegramSession(), player: Player(),
                       artwork: CoverArtwork.shared, library: Library.shared)
    }
}
