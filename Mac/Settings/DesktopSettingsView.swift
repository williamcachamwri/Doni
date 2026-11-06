import AppKit
import Support
import SwiftUI
import TdSession
import TelegramDesignSystem

/// The settings window: one scroll of cards, the phone's content, the reference's shape.
///
/// MeloX's panels (`DesktopAccountView`, `DesktopSettingsView`) are a caption over a rounded dark card
/// of rows — a tinted glyph, the row's name, its value or a chevron at the trailing edge, dividers
/// that start after the glyph — with one accent pill at the bottom right that closes it. Doni draws
/// the same shapes here because the two screens are the same screen with a pointer instead of a thumb;
/// what changes is only that the desktop has room to show the bytes and the cleanups inline rather than
/// behind a navigation push.
///
/// The content is the phone's, in the phone's order: the account and the way out, the language, what
/// the library holds and what it can throw away, the words, which channels may be read, the version.
struct DesktopSettingsView: View {
    @Environment(DesktopAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: TelegramSession
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var artwork: CoverArtwork

    @State private var showsReset = false
    @State private var usage: DoniStorage?
    @State private var cleaning: StorageCleanup?
    @State private var message: String?
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if session.isAuthorized {
                        accountCard
                        appCard
                        libraryCard
                        storageCard
                        lyricsCard
                        channelsCard
                        aboutCard
                        if let message {
                            Text(message)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Chưa đăng nhập")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Khôi phục cài đặt…", role: .destructive) { showsReset = true }

                Spacer()

                Button("Hoàn tất") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(MusicTint.accent)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .frame(height: 62)
        }
        .frame(width: 650, height: 620)
        .task { await measure() }
        .alert("Khôi phục cài đặt?", isPresented: $showsReset) {
            Button("Khôi phục", role: .destructive) { resetPreferences() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Lời bài hát và tuỳ chọn kiểm tra cập nhật trở lại như lúc mới cài. Ngôn ngữ giữ nguyên vì nó chỉ đổi được khi mở lại app.")
        }
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

    // MARK: Cards

    private var accountCard: some View {
        SettingsCard(title: nil) {
            SettingsRow(symbol: "person.crop.circle", title: name, subtitle: handleLine) {
                DesktopAccountMark(size: 38)
            }

            SettingsDivider()

            SettingsRow(symbol: "music.note.list", title: "Thư viện", subtitle: counts) { EmptyView() }

            SettingsDivider()

            SettingsRow(symbol: "rectangle.portrait.and.arrow.right",
                        title: "Đăng xuất",
                        destructive: true,
                        action: { model.ui.sheet = .account }) {
                Chevron()
            }
        }
    }

    private var appCard: some View {
        SettingsCard(title: "Ứng dụng") {
            SettingsRow(symbol: "globe", title: "Ngôn ngữ",
                        subtitle: "Đổi ngôn ngữ có hiệu lực khi mở lại Doni.") {
                DesktopLanguagePicker()
            }
        }
    }

    private var libraryCard: some View {
        SettingsCard(title: "Thư viện nhạc") {
            SettingsRow(symbol: "doc.text", title: "Bài đã chỉ mục",
                        subtitle: "Lấy từ các kênh đã chọn") {
                SettingsValue(library.trackCount.formatted())
            }

            SettingsDivider()

            SettingsRow(symbol: "arrow.down.circle", title: "Đã tải về máy",
                        subtitle: "Nghe được khi không có mạng") {
                SettingsValue(localized("%@ bài", library.downloadedCount.formatted()))
            }
        }
    }

    /// The bytes and the two things that throw them away — the phone's storage screen, inline, because
    /// a desktop window has the room and a settings screen should not hide a number the listener is
    /// asking for behind another click.
    private var storageCard: some View {
        SettingsCard(title: "Bộ nhớ") {
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

            ForEach(Array(StorageCleanup.allCases.enumerated()), id: \.element.id) { index, action in
                SettingsDivider()
                SettingsRow(symbol: action == .pictures ? "photo" : "trash",
                            title: action.title,
                            destructive: true,
                            action: { cleaning = action }) {
                    Chevron()
                }
            }
        }
    }

    private var lyricsCard: some View {
        SettingsCard(title: "Lời bài hát") {
            DesktopLyricsRows()
        }
    }

    private var channelsCard: some View {
        SettingsCard(title: "Kênh nhạc") {
            if library.channels.isEmpty {
                SettingsRow(symbol: "antenna.radiowaves.left.and.right",
                            title: "Chưa thêm kênh nào") { EmptyView() }
            } else {
                ForEach(Array(library.channels.enumerated()), id: \.element.chatId) { index, channel in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(symbol: "antenna.radiowaves.left.and.right",
                                title: channel.title,
                                subtitle: subtitle(for: channel)) {
                        DesktopChannelIndexToggle(channel: channel)
                    }
                }
            }
        }
    }

    private var aboutCard: some View {
        SettingsCard(title: "Giới thiệu") {
            SettingsRow(symbol: "info.circle", title: "Phiên bản",
                        subtitle: localized("Bản dựng %@", AppVersion.build)) {
                SettingsValue(AppVersion.current)
            }

            SettingsDivider()

            SettingsRow(symbol: "arrow.triangle.2.circlepath",
                        title: "Kiểm tra cập nhật khi mở app") {
                DesktopUpdateCheckToggle()
            }
        }
    }

    // MARK: Words the cards say

    /// A person's name is not a catalog key in any language, so it is drawn as Telegram sent it.
    private var name: String {
        session.account?.name ?? "Chưa đăng nhập"
    }

    private var handleLine: String? {
        guard let account = session.account, !account.username.isEmpty else { return nil }
        return "@\(account.username)"
    }

    private var counts: String {
        [
            localized("%@ bài", library.trackCount.formatted()),
            localized("%@ kênh", library.channels.count.formatted()),
            localized("%@ danh sách", library.playlists.count.formatted()),
        ].joined(separator: " · ")
    }

    private func subtitle(for channel: StoreChannel) -> String {
        let songs = localized("%@ bài", library.store.trackCount(chatId: channel.chatId).formatted())
        let handle = channel.username.isEmpty ? nil : "@\(channel.username)"
        return [handle, songs].compactMap { $0 }.joined(separator: " · ")
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

    /// Doni has no player engine to reset — no equaliser, no sleep timer, no recognition — so what this
    /// returns is the words and the launch check. The language is left alone because it cannot change
    /// without a relaunch, and a reset that appeared to change it would be lying.
    private func resetPreferences() {
        let words = LyricsPreferences.shared
        words.networkAllowed = true
        words.offset = 0
        words.showPlain = true
        AppUpdateSettings.checksOnLaunch = true
    }
}

// MARK: - The card shapes

/// A caption over one rounded panel.
struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.055),
                        in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
        }
    }
}

/// One row: a tinted glyph, the name with its caption under it, and whatever answers at the right.
struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var destructive = false
    var action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(symbol: String, title: String, subtitle: String? = nil, destructive: Bool = false,
         action: @escaping () -> Void = {},
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.destructive = destructive
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MusicTint.accent)
                    .frame(width: 30, height: 30)
                    .background(MusicTint.accent.opacity(0.13),
                                in: .rect(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(destructive ? MusicTint.accent : Color.primary)
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 10)

                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 54, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The divider starts after the glyph, the way the reference's cards do it.
struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 56)
    }
}

struct SettingsValue: View {
    let text: String
    var isBold = false

    init(_ text: String, bold: Bool = false) {
        self.text = text
        isBold = bold
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: isBold ? .semibold : .regular))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Controls that own their own state

private struct DesktopLanguagePicker: View {
    @State private var language = DoniLanguage.current
    @State private var needsRestart = false

    var body: some View {
        Picker("Ngôn ngữ", selection: $language) {
            ForEach(DoniLanguage.allCases) { option in
                Text(option.nativeName).tag(option)
            }
        }
        .labelsHidden()
        .fixedSize()
        .onChange(of: language) { _, chosen in
            DoniLanguage.apply(chosen)
            needsRestart = true
        }
        .alert("Mở lại Doni?", isPresented: $needsRestart) {
            Button("Thoát ra") { NSApplication.shared.terminate(nil) }
            Button("Để sau", role: .cancel) {}
        } message: {
            Text("Ngôn ngữ mới hiện ra từ lần mở kế tiếp.")
        }
    }
}

private struct DesktopUpdateCheckToggle: View {
    @State private var on = AppUpdateSettings.checksOnLaunch

    var body: some View {
        Toggle("Kiểm tra cập nhật khi mở app", isOn: $on)
            .labelsHidden()
            .toggleStyle(.switch)
            .onChange(of: on) { _, value in
                AppUpdateSettings.checksOnLaunch = value
            }
    }
}

/// Where the words come from and when they move — the three settings the phone keeps in the words
/// screen and the desktop has no other place for.
private struct DesktopLyricsRows: View {
    @ObservedObject private var prefs = LyricsPreferences.shared

    var body: some View {
        SettingsRow(symbol: "network", title: "Tải lời từ mạng",
                    subtitle: "Tắt thì Doni chỉ hiện lời đã có trên máy.") {
            Toggle("Tải lời từ mạng", isOn: $prefs.networkAllowed)
                .labelsHidden()
                .toggleStyle(.switch)
        }

        SettingsDivider()

        SettingsRow(symbol: "text.quote", title: "Hiện lời không có thời gian") {
            Toggle("Hiện lời không có thời gian", isOn: $prefs.showPlain)
                .labelsHidden()
                .toggleStyle(.switch)
        }

        SettingsDivider()

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Lệch thời gian")
                    .font(.system(size: 13.5, weight: .medium))
                Spacer()
                SettingsValue(offsetLine)
            }
            Slider(value: $prefs.offset, in: -10...10, step: 0.1)
            Text("Với một bản lời được canh theo một bản thu khác.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var offsetLine: String {
        let seconds = prefs.offset
        guard abs(seconds) >= 0.05 else { return localized("0 giây") }
        let magnitude = abs(seconds).formatted(.number.precision(.fractionLength(1)))
        return localized(seconds < 0 ? "-%@ giây" : "+%@ giây", magnitude)
    }
}

/// Whether a channel may be read into the library. Turning it off is not just a flag: the walk has to
/// run again, or the songs it already wrote stay where they are and the switch looks like it did
/// nothing.
private struct DesktopChannelIndexToggle: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var session: TelegramSession
    let channel: StoreChannel

    var body: some View {
        Toggle("Kênh", isOn: Binding(get: { channel.isIndexed }, set: { on in
            let store = library, chats = session
            store.setIndexed(channel.chatId, on: on)
            model.indexer.run(chats, library: store)
        }))
        .labelsHidden()
        .toggleStyle(.switch)
    }
}
