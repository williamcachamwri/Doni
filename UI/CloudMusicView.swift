import SwiftUI
import Support
import TelegramDesignSystem
import UIKit
import UniformTypeIdentifiers

/// The tab MeloX puts its cloud drive in (`Features/Cloud/CloudMusicView.swift:99-206`), and Doni's
/// cloud is the thing Telegram actually has: **Saved Messages**.
///
/// The reference's cloud is a NetEase drive — songs on someone else's server, listed with the same
/// plain rows as its local library, with a quota over the top and a device-side copy made by tapping.
/// Here the server is the account's own chat, so the list is that chat's history and the upload is a
/// `sendMessage` with the file in it. A song picked out of the Files app is therefore *sent*, not
/// copied: once Telegram has the bytes the staged copy is deleted, so the song lives in one place and
/// the phone keeps only what streaming needed.
///
/// Rows the earlier builds copied into the sandbox are still listed and still playable. They are the
/// user's music and this screen has no right to forget them; what changed is where new songs go.
struct CloudMusicView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    /// The account's own chat, read and written by the same object the Now Playing menu uses, so the
    /// two surfaces agree about what is already in the cloud.
    @StateObject private var cloud = CloudMusic()

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
    /// Which of the two destinations the next picker answer goes to: Telegram, or the phone only.
    /// Held as state because the picker's callback is one function and the choice is made a tap
    /// before it.
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
                        // No downloader: the cover of a file the phone owns is read out of the file,
                        // which is the first thing `CoverArtwork` tries and the only thing it needs.
                        await artwork.load(track: track, side: MusicSearchMetrics.songArt)
                    }
                    .swipeActions(edge: .trailing) {
                        // Only a row the phone owns can be deleted here. A Saved Messages row is a
                        // message in the user's Telegram, and taking it out of the app's list would
                        // be a lie about what was removed — or, if it deleted for real, the song.
                        if track.isLocal {
                            Button(role: .destructive) {
                                pendingDeletion = track
                            } label: {
                                Label("Xoá", systemImage: "trash")
                            }
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
                .accessibilityLabel(importing > 0 ? "Đang thêm nhạc…" : "Thêm nhạc từ file")
            }
        }
        .task {
            await cloud.refresh(session)
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
                library.removeLocal(song)
                pendingDeletion = nil
            }
            Button("Huỷ", role: .cancel) {}
        } message: { _ in
            Text("Bài này sẽ mất khỏi Doni. Tệp gốc bạn đã chọn vẫn còn ở nơi nó đang nằm.")
        }
        .alert("Không thêm được bài", isPresented: cloudFailing) {
            Button("OK", role: .cancel) { cloud.failure = nil }
        } message: {
            Text(cloud.failure ?? "")
        }
        .alert("Không thêm được bài", isPresented: failing) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "File không đọc được.")
        }
        .overlay {
            if visible.isEmpty && importing == 0 && !cloud.isBusy {
                emptyState
            }
        }
    }

    // MARK: What the list is

    /// The songs that are the user's own: what Telegram holds in Saved Messages, then what an older
    /// build copied into the sandbox. Newest first, the order `Library` reads its track table in.
    private var kept: [StoreTrack] {
        cloud.songs + library.storedTracks.filter(\.isLocal)
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
    ///
    /// Cloud songs are counted by their size on Telegram's side, which is the honest number for a
    /// library that is not on the phone.
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

    /// Where a picker's answer goes. Split out because the sheet's own closure had grown to the
    /// point the compiler gave up type-checking it, which is the sign a view body is carrying two
    /// decisions rather than one.
    private func picked(_ urls: [URL]) {
        print("cloud picker returned \(urls.count) urls")
        showsFileImporter = false
        if picksForCloud {
            Task { await cloud.upload(session, urls: urls) }
        } else {
            importFiles(urls)
        }
    }

    /// One picker, as many files as were selected. Hashing and copying are a few hundred milliseconds
    /// of disk each, so they run one after another rather than all at once, and the count at the head
    /// of the list ticks down as they land — the only progress a user can act on.
    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        // The permission the Files app grants for a picked file is only alive inside the callback it
        // was handed in, so it is claimed here — synchronously, on the main actor, before anything
        // awaits. Claimed later, from the task below, it answers false for every file and the whole
        // import reads as "not one of these opened".
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
                    // The first refusal, with the name it refused. A screen that only says "none of
                    // these opened" cannot be answered by the person standing in front of it.
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

/// The Files picker, asked for a private copy rather than a borrowed reference.
///
/// SwiftUI's `fileImporter` hands back the source URL and relies on a security-scoped permission
/// whose lifetime is easy to lose before a background import reads it. `asCopy: true` makes the
/// system copy the chosen song into this app's sandbox first, which is exactly what Doni needs:
/// the importer then hashes and copies a file that is already reachable.
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
