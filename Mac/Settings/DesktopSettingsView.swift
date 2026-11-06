import AppKit
import Support
import SwiftUI
import TdSession
import TelegramDesignSystem

/// The settings window, in the reference's shape (`DesktopSettingsView.swift:13-117`): a `TabView` of
/// `Form`s over a divider and a footer, the whole window re-sized per tab, mounted in the app's
/// `Settings` scene so ⌘, is the system's own way in.
///
/// The four tabs are the four things Doni can be told about: what language it speaks and what it looks
/// for when it starts; when its words arrive late; what it is keeping on the disk; which channels it may
/// read. The reference's other tabs are NetEase's own features — song recognition, auto-mix, a region
/// picker — and a settings screen that offers a switch for something the app does not do is worse than a
/// short one.
struct DesktopSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = DesktopSettingsTab.general

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                DesktopGeneralSettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tabItem { Label("Chung", systemImage: "gearshape") }
                    .tag(DesktopSettingsTab.general)

                DesktopLyricsSettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tabItem { Label("Lời bài hát", systemImage: "text.quote") }
                    .tag(DesktopSettingsTab.lyrics)

                DesktopStorageSettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tabItem { Label("Bộ nhớ", systemImage: "internaldrive") }
                    .tag(DesktopSettingsTab.storage)

                DesktopChannelSettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tabItem { Label("Kênh nhạc", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(DesktopSettingsTab.channels)
            }
            .tabViewStyle(.automatic)
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                Spacer()
                Button("Đóng") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .frame(width: 650, height: selection.contentHeight)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: selection)
    }
}

private enum DesktopSettingsTab: Hashable {
    case general, lyrics, storage, channels

    /// The reference's own trick (`:108-116`): a settings window that grows to the tab it is showing
    /// rather than scrolling inside a fixed one.
    var contentHeight: CGFloat {
        switch self {
        case .general: 470
        case .lyrics: 300
        case .storage: 430
        case .channels: 430
        }
    }
}

// MARK: - Chung

private struct DesktopGeneralSettingsView: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var session: TelegramSession

    @State private var language = DoniLanguage.current
    @State private var checksOnLaunch = AppUpdateSettings.checksOnLaunch
    @State private var needsRestart = false
    @State private var update: UpdateAlert?

    var body: some View {
        Form {
            Section("Ngôn ngữ") {
                Picker("Ngôn ngữ", selection: $language) {
                    ForEach(DoniLanguage.allCases) { option in
                        Text(option.nativeName).tag(option)
                    }
                }
                .onChange(of: language) { _, chosen in
                    // The system reads the language list when the process starts, so the choice lands
                    // next launch — which is what the footer says rather than what a silent switch would.
                    DoniLanguage.apply(chosen)
                    needsRestart = true
                }
            }

            Section("Tài khoản") {
                HStack(spacing: 12) {
                    DesktopAccountMark(size: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        name
                            .font(.headline)
                        if let handle = handle {
                            Text("@\(handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                    Button("Chi tiết") { model.ui.sheet = .account }
                }
            }

            Section("Khởi động") {
                Toggle("Kiểm tra cập nhật khi mở app", isOn: $checksOnLaunch)
                    .onChange(of: checksOnLaunch) { _, on in
                        AppUpdateSettings.checksOnLaunch = on
                    }
                Button("Kiểm tra cập nhật ngay") {
                    Task {
                        do {
                            let result = try await AppUpdateService.check()
                            update = result.hasUpdate
                                ? .available(result, version: AppVersion.current)
                                : .current(version: AppVersion.current)
                        } catch {
                            update = .failed(error)
                        }
                    }
                }
            }

            Section("Giới thiệu") {
                LabeledContent("Phiên bản", value: AppVersion.current)
                LabeledContent("Bản dựng", value: AppVersion.build)
            }
        }
        .formStyle(.columns)
        .padding()
        .alert("Mở lại Doni?", isPresented: $needsRestart) {
            Button("Thoát ra") { NSApplication.shared.terminate(nil) }
            Button("Để sau", role: .cancel) {}
        } message: {
            Text("Ngôn ngữ mới hiện ra từ lần mở kế tiếp.")
        }
        .updateAlert($update)
    }

    /// A person's name is not a catalog key in any language, so it is drawn as Telegram sent it — except
    /// the no-account case, which is a sentence.
    private var name: Text {
        guard let account = session.account else { return Text("Chưa đăng nhập") }
        return Text(account.name)
    }

    private var handle: String? {
        guard let account = session.account, !account.username.isEmpty else { return nil }
        return account.username
    }
}

// MARK: - Lời bài hát

private struct DesktopLyricsSettingsView: View {
    @ObservedObject private var prefs = LyricsPreferences.shared

    var body: some View {
        Form {
            Section("Nguồn") {
                Toggle("Tải lời từ mạng", isOn: $prefs.networkAllowed)
                Text("Tắt thì Doni chỉ hiện lời đã có trên máy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Hiện lời không có thời gian", isOn: $prefs.showPlain)
            }

            Section("Thời gian") {
                LabeledContent("Lệch thời gian") {
                    Text(offsetLine)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $prefs.offset, in: -10...10, step: 0.1) {
                    Text("Lệch thời gian")
                }
                Button("Đặt lại 0 giây") { prefs.offset = 0 }
                Text("Với một bản lời được canh theo một bản thu khác.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.columns)
        .padding()
    }

    /// `+2,5 giây` / `0 giây`: the sign is the point of the row, so it is spelled out rather than left
    /// to a number formatter that drops the plus.
    private var offsetLine: String {
        let seconds = prefs.offset
        guard abs(seconds) >= 0.05 else { return localized("0 giây") }
        let magnitude = abs(seconds).formatted(.number.precision(.fractionLength(1)))
        return localized(seconds < 0 ? "-%@ giây" : "+%@ giây", magnitude)
    }
}

// MARK: - Bộ nhớ

private struct DesktopStorageSettingsView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var session: TelegramSession
    @EnvironmentObject private var artwork: CoverArtwork

    @State private var usage: DoniStorage?
    @State private var isMeasuring = false
    @State private var cleaning: StorageCleanup?
    @State private var message: String?
    @State private var failure: String?

    var body: some View {
        Form {
            Section("Bộ nhớ đã dùng") {
                bytes("arrow.down.circle.fill", "Nhạc Telegram",
                      "Bài đầy đủ và cache stream từng phần", usage?.telegramBytes)
                bytes("externaldrive", "Nhạc bạn thêm",
                      "File chọn từ máy, không lấy lại được", usage?.importedBytes)
                bytes("photo.stack", "Cache ảnh",
                      "Ảnh bìa và ảnh kênh, tự tải lại", usage?.pictureBytes)
                bytes("heart.text.square", "Thư viện của bạn",
                      "Danh sách, bài yêu thích, ảnh bìa bạn chọn", usage?.libraryBytes)
                bytes("gearshape.2", "Phần Telegram của app",
                      "Cơ sở dữ liệu TDLib tự tạo — không xoá được khi đang đăng nhập",
                      usage?.engineBytes)
                LabeledContent("Tổng") {
                    Text(DataSize.string(usage?.managedBytes ?? 0))
                        .font(.headline)
                        .contentTransition(.numericText())
                }
            }

            Section("Dọn dẹp") {
                ForEach(StorageCleanup.allCases) { action in
                    cleanupRow(action)
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.columns)
        .padding()
        .task { await measure() }
        .confirmationDialog(LocalizedStringKey(cleaning?.title ?? ""),
                            isPresented: confirming, titleVisibility: .visible) {
            if let action = cleaning {
                Button(LocalizedStringKey(action.confirmTitle), role: .destructive) {
                    Task { await perform(action) }
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(cleaning?.confirmMessage ?? ""))
        }
        .alert("Không dọn được", isPresented: failing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func bytes(_ symbol: String, _ title: String, _ subtitle: String,
                       _ value: Int64?) -> some View {
        LabeledContent {
            Text(DataSize.string(value ?? 0))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
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

    private func cleanupRow(_ action: StorageCleanup) -> some View {
        LabeledContent {
            Button(LocalizedStringKey(action.confirmTitle)) { cleaning = action }
                .disabled(cleaning != nil)
        } label: {
            Text(LocalizedStringKey(action.title))
        }
    }

    private var confirming: Binding<Bool> {
        Binding(get: { cleaning != nil }, set: { shown in if !shown { cleaning = nil } })
    }

    private var failing: Binding<Bool> {
        Binding(get: { failure != nil }, set: { shown in if !shown { failure = nil } })
    }

    private func measure() async {
        guard !isMeasuring else { return }
        isMeasuring = true
        defer { isMeasuring = false }
        await library.remeasureDisk()
        usage = library.disk
    }

    private func perform(_ action: StorageCleanup) async {
        guard cleaning == nil else { return }
        cleaning = action
        message = nil
        defer { cleaning = nil }

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
}

// MARK: - Kênh

private struct DesktopChannelSettingsView: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var session: TelegramSession

    var body: some View {
        Form {
            if library.channels.isEmpty {
                Section("Kênh nhạc") {
                    Text("Chưa thêm kênh nào")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(library.channels) { channel in
                        Toggle(isOn: indexed(channel)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.title)
                                Text(subtitle(for: channel))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Kênh nhạc")
                } footer: {
                    Text("Bỏ một kênh khỏi danh sách ngừng đưa bài của nó vào thư viện; nhạc đã tải vẫn còn trên máy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.columns)
        .padding()
    }

    /// Turning a channel off is not just a flag: the walk has to run again, or the songs it already put
    /// in the library stay where they are and the switch looks like it did nothing.
    private func indexed(_ channel: StoreChannel) -> Binding<Bool> {
        Binding(get: { channel.isIndexed }, set: { on in
            let store = library, chats = session
            store.setIndexed(channel.chatId, on: on)
            model.indexer.run(chats, library: store)
        })
    }

    private func subtitle(for channel: StoreChannel) -> String {
        let songs = localized("%@ bài", library.store.trackCount(chatId: channel.chatId).formatted())
        let handle = channel.username.isEmpty ? nil : "@\(channel.username)"
        return [handle, songs].compactMap { $0 }.joined(separator: " · ")
    }
}
