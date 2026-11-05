import SwiftUI
import Support
import TelegramDesignSystem

/// The screen MeloX puts behind its settings' storage entry: an overview of what the app holds and
/// what the phone has left, one row per kind of byte, and a button for each of the two things that
/// can be thrown away (`StorageManagementView.swift:10-467`).
///
/// The reference's numbers come from a server it owns, so its screen is a maintenance panel for a
/// cache that always refills itself. Doni's is the same shape with a different job: the app had been
/// quoting its own rows — a report of what it meant to keep — while TDLib went on holding several
/// hundred megabytes of streamed songs that no row ever marked. Every figure here is measured off the
/// disk, which is the number the system's own panel charges the app.
///
/// The two buckets that are not here on purpose: a file the user imported, which no server can hand
/// back, and the picture a user chose for a list, whose only copy is the file this app wrote. Both
/// are counted, and neither is a button.
struct StorageView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    /// The measurement lives on the library, because the settings line above this screen quotes the
    /// same number and a cleanup here would otherwise leave it stale.
    private var usage: DoniStorage? { library.disk }

    @State private var isMeasuring = false
    /// The cleanup running right now, which is the row wearing a spinner.
    @State private var active: StorageCleanup?
    /// The cleanup being asked about. Held as the dialog's item rather than a plain flag, because
    /// the dialog can be dismissed by anything else that takes focus.
    @State private var confirming: StorageCleanup?
    @State private var message: String?
    @State private var failure: String?

    var body: some View {
        List {
            overview
            items
            cleanup
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bộ nhớ")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await measure() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await measure() }
                } label: {
                    if isMeasuring {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isMeasuring || active != nil)
                .accessibilityLabel("Đếm lại")
            }
        }
        .task { await measure() }
        .confirmationDialog(
            confirming?.title ?? "Xoá?",
            isPresented: confirmingPresented,
            titleVisibility: .visible,
            presenting: confirming
        ) { action in
            Button(LocalizedStringKey(action.confirmTitle), role: .destructive) {
                confirming = nil
                Task { await perform(action) }
            }
            Button("Huỷ", role: .cancel) {}
        } message: { action in
            Text(LocalizedStringKey(action.confirmMessage))
        }
        .alert("Không dọn được", isPresented: failing) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "Hệ thống không cho phép xoá.")
        }
    }

    // MARK: Overview

    /// What the app holds, on the reference's own box: a 34 pt tinted glyph, the label over the
    /// number at 2 pt, 14 to the capacity bar, and 6 pt of vertical padding in the row
    /// (`StorageManagementView.swift:68-124`).
    private var overview: some View {
        Section {
            VStack(alignment: .leading, spacing: MusicStorageMetrics.overviewGap) {
                HStack(spacing: MusicStorageMetrics.rowGap) {
                    Image(systemName: "internaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: MusicStorageMetrics.glyphBox,
                               height: MusicStorageMetrics.glyphBox)

                    VStack(alignment: .leading, spacing: MusicStorageMetrics.textGap) {
                        Text("Doni giữ trên máy")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let usage {
                            Text(DataSize.string(usage.managedBytes))
                                .font(.title2.weight(.semibold))
                                .contentTransition(.numericText())
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }

                if let used = usage?.deviceUsedBytes, let total = usage?.deviceTotalBytes {
                    VStack(alignment: .leading, spacing: MusicStorageMetrics.textGap) {
                        ProgressView(value: Double(used), total: Double(max(total, 1)))
                            .tint(.accentColor)
                        HStack {
                            Text(localized("Máy đã dùng %@", DataSize.string(used)))
                            Spacer()
                            Text(localized("Còn trống %@", DataSize.string(usage?.deviceFreeBytes ?? 0)))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, MusicStorageMetrics.rowVertical)

            LabeledContent("Xoá được",
                           value: DataSize.string(usage?.reclaimableBytes ?? 0))

            if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Tổng quan")
        } footer: {
            Text("Nhạc Telegram và cache ảnh lấy lại được khi cần. Danh sách, bài yêu thích, ảnh bìa bạn tự chọn và file bạn thêm vào thì không. Phần TDLib tự tạo không phải dữ liệu của bạn: đăng xuất sẽ xoá sạch, và phiên mới lại tạo nó từ đầu.")
        }
    }

    // MARK: What is where

    /// One row per kind of byte, the value on the right in the reference's `LabeledContent`
    /// (`StorageManagementView.swift:150-190`, `:329-352`).
    private var items: some View {
        Section("Bộ nhớ đã dùng") {
            item("arrow.down.circle.fill", "Nhạc Telegram",
                 "Bài và ảnh TDLib đã tải về", usage?.telegramBytes)
            item("externaldrive", "Nhạc bạn thêm",
                 "File chọn từ máy, không lấy lại được", usage?.importedBytes)
            item("photo.stack", "Cache ảnh",
                 "Ảnh bìa và ảnh kênh, tự tải lại", usage?.pictureBytes)
            item("heart.text.square", "Thư viện của bạn",
                 "Danh sách, bài yêu thích, ảnh bìa bạn chọn", usage?.libraryBytes)
            // Its own row, because a fresh TDLib spends several megabytes on its database, its
            // binary log and its sticker folders before it has been told anything at all. Counted
            // with the library, that made a sign-out that worked look like one that failed.
            item("gearshape.2", "Phần Telegram của app",
                 "Cơ sở dữ liệu TDLib tự tạo — không xoá được khi đang đăng nhập",
                 usage?.engineBytes)
        }
    }

    private func item(_ symbol: String, _ title: String, _ subtitle: String,
                      _ bytes: Int64?) -> some View {
        LabeledContent {
            Text(DataSize.string(bytes ?? 0))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        } label: {
            Label {
                VStack(alignment: .leading, spacing: MusicStorageMetrics.textGap) {
                    Text(LocalizedStringKey(title))
                    Text(LocalizedStringKey(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: Cleaning

    /// The two buttons, each wearing the bytes it is about: the reference puts the size where the
    /// spinner goes, so a row says what it will free before it is pressed and works while it does
    /// (`StorageManagementView.swift:192-229`, `:354-418`).
    private var cleanup: some View {
        Section {
            button(.pictures, "eraser", "Xoá cache ảnh",
                   "Ảnh bìa và ảnh kênh sẽ được tải lại khi cần",
                   usage?.pictureBytes)
            button(.downloads, "trash", "Xoá nhạc Telegram đã tải",
                   "Bài nào cũng nghe lại được sau",
                   usage?.telegramBytes,
                   disabled: player.isFetchingFile || library.downloadedCount == 0)
        } header: {
            Text("Dọn dẹp")
        } footer: {
            if player.isFetchingFile {
                Text("Đang tải một bài về máy — dọn xong sẽ phải tải lại chính bài đó.")
            }
        }
    }

    private func button(_ action: StorageCleanup, _ symbol: String, _ title: String,
                        _ subtitle: String, _ bytes: Int64?, disabled: Bool = false) -> some View {
        Button {
            confirming = action
        } label: {
            HStack(spacing: MusicStorageMetrics.rowGap) {
                Label {
                    VStack(alignment: .leading, spacing: MusicStorageMetrics.textGap) {
                        Text(LocalizedStringKey(title))
                        Text(LocalizedStringKey(subtitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: symbol)
                }

                Spacer(minLength: MusicStorageMetrics.valueFloor)

                if active == action {
                    ProgressView().controlSize(.small)
                } else if let bytes {
                    Text(DataSize.string(bytes))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(active != nil || disabled)
    }

    // MARK: Work

    private func measure() async {
        guard !isMeasuring else { return }
        isMeasuring = true
        defer { isMeasuring = false }
        await library.remeasureDisk()
    }

    /// Doing one cleanup, then counting again — the screen's whole purpose is that its numbers are
    /// the disk's, so a button that throws bytes away has to go and look at what is left.
    private func perform(_ action: StorageCleanup) async {
        guard active == nil else { return }
        active = action
        message = nil
        defer { active = nil }

        switch action {
        case .pictures:
            let freed = StorageTally.clearPictures(artwork)
            message = localized("Đã giải phóng %@ ảnh.", DataSize.string(freed))
        case .downloads:
            guard let files = session.covers() else {
                failure = "Chưa có kết nối Telegram, nên không thể báo cho TDLib biết các bài này đã không còn trên máy."
                return
            }
            let count = await library.clearTelegramDownloads(with: files)
            message = count == 1
                ? "Đã xoá 1 bài khỏi máy."
                : localized("Đã xoá %@ bài khỏi máy.", count.formatted())
        }
        await measure()
    }

    private var confirmingPresented: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { shown in if !shown { confirming = nil } })
    }

    private var failing: Binding<Bool> {
        Binding(get: { failure != nil }, set: { shown in if !shown { failure = nil } })
    }
}

/// The two things the screen will throw away, and what each one says before it is allowed to.
enum StorageCleanup: String, Identifiable {
    case pictures
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pictures: return "Xoá cache ảnh?"
        case .downloads: return "Xoá nhạc Telegram đã tải?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .pictures: return "Xoá cache"
        case .downloads: return "Xoá hết nhạc"
        }
    }

    var confirmMessage: String {
        switch self {
        case .pictures:
            return "Doni sẽ tải lại ảnh bìa và ảnh kênh khi cần. Ảnh bạn tự chọn cho một danh sách không nằm trong số này."
        case .downloads:
            return "Nhạc tải từ Telegram về máy sẽ bị xoá. Danh sách và bài yêu thích vẫn còn, và bài nào cũng tải lại được. File bạn thêm vào ở Cloud Music không bị đụng tới."
        }
    }
}

#Preview {
    NavigationStack {
        StorageView(session: TelegramSession(), player: Player(),
                    artwork: CoverArtwork.shared, library: Library.shared)
    }
}
