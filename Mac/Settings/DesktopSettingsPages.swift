import Support
import SwiftUI
import TelegramDesignSystem

/// The storage page the library card's door opens: every byte line and the two cleanups, as the
/// phone's StorageView says them — a page of its own because a page is what can throw bytes away,
/// and the settings scroll is not that page (`SettingsView.swift:143-146`).
struct DesktopStoragePage: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var session: TelegramSession
    @EnvironmentObject private var artwork: CoverArtwork

    @State private var usage: DoniStorage?
    @State private var cleaning: StorageCleanup?
    @State private var message: String?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsCard(title: nil) {
                    SettingsRow(symbol: "arrow.down.circle.fill", title: "Nhạc Telegram",
                                subtitle: "Bài đầy đủ và cache stream từng phần") {
                        SettingsValue(DataSize.string(usage?.telegramBytes ?? 0))
                    }
                    SettingsDivider()
                    SettingsRow(symbol: "externaldrive", title: "Nhạc bạn thêm",
                                subtitle: "File chọn từ máy, không lấy lại được") {
                        SettingsValue(DataSize.string(usage?.importedBytes ?? 0))
                    }
                    SettingsDivider()
                    SettingsRow(symbol: "photo.stack", title: "Cache ảnh",
                                subtitle: "Ảnh bìa và ảnh kênh, tự tải lại") {
                        SettingsValue(DataSize.string(usage?.pictureBytes ?? 0))
                    }
                    SettingsDivider()
                    SettingsRow(symbol: "heart.text.square", title: "Thư viện của bạn",
                                subtitle: "Danh sách, bài yêu thích, ảnh bìa bạn chọn") {
                        SettingsValue(DataSize.string(usage?.libraryBytes ?? 0))
                    }
                    SettingsDivider()
                    SettingsRow(symbol: "gearshape.2", title: "Phần Telegram của app",
                                subtitle: "Cơ sở dữ liệu TDLib tự tạo — không xoá được khi đang đăng nhập") {
                        SettingsValue(DataSize.string(usage?.engineBytes ?? 0))
                    }
                    SettingsDivider()
                    SettingsRow(symbol: "internaldrive", title: "Tổng") {
                        SettingsValue(DataSize.string(usage?.managedBytes ?? 0), bold: true)
                    }

                    ForEach(Array(StorageCleanup.allCases.enumerated()), id: \.element.id) { _, action in
                        SettingsDivider()
                        SettingsRow(symbol: action == .pictures ? "photo" : "trash",
                                    title: action.title,
                                    destructive: true,
                                    action: { cleaning = action }) {
                            Chevron()
                        }
                    }
                }

                if let message {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Bộ nhớ")
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

    private var confirming: Binding<Bool> {
        Binding(get: { cleaning != nil }, set: { shown in if !shown { cleaning = nil } })
    }

    private var failing: Binding<Bool> {
        Binding(get: { failure != nil }, set: { shown in if !shown { failure = nil } })
    }

    private func measure() async {
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

/// The words page: the three lyrics settings the phone has not grown a screen for yet, so the
/// desktop gives them the page its own idiom promises — one door in the settings scroll, one room
/// behind it.
struct DesktopLyricsPage: View {
    var body: some View {
        ScrollView {
            SettingsCard(title: nil) {
                DesktopLyricsRows()
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Lời bài hát")
    }
}
