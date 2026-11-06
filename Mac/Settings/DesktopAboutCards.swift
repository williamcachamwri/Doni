import SwiftUI
import TelegramDesignSystem

/// The About page the settings panel pushes: the phone's About screen, word for word, in the
/// desktop's card furniture. The phone pushes it onto its settings stack; the panel pushes it onto
/// its own NavigationStack, and the menu's about row opens the panel with this page already on top.
struct DesktopAboutPage: View {
    var body: some View {
        ScrollView {
            DesktopAboutSection()
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Giới thiệu Doni")
    }
}

/// The phone's About screen, worn as cards inside the desktop's settings panel.
///
/// Every word is the phone's word — the same catalog keys, the same licence lines read from
/// `AppAbout`, the same three answers a version check can give — because two shells saying two
/// different things about the same app is how a port admits it drifted. What differs is only the
/// furniture: the phone pushes ReleaseNotesView and LicensesView onto a stack, the desktop has the
/// room to lay the licences inline and lifts the notes into a sheet.
struct DesktopAboutSection: View {
    @Environment(\.openURL) private var openURL

    @State private var notes = AppReleaseNotes.load()
    @State private var showsNotes = false
    @State private var isChecking = false
    @State private var alert: UpdateAlert?

    private var version: String { AppVersion.displayName(AppVersion.current) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            identityCard
            updateCard
            caption("Tự động kiểm tra chỉ báo khi có bản mới; kiểm tra hỏng thì im lặng.")
            aboutCard
            copyrightCard
            licensesCard
            caption("Bản đầy đủ của GPL-3.0 nằm trong file LICENSE của kho mã.")
            disclaimerCard
        }
        .sheet(isPresented: $showsNotes) {
            DesktopReleaseNotesSheet(notes: notes)
        }
        .updateAlert($alert)
    }

    private var identityCard: some View {
        SettingsCard(title: nil) {
            VStack(spacing: 10) {
                DoniLogo(side: 72)
                Text("Doni").font(.system(size: 17, weight: .bold))
                Text("Máy nghe nhạc Telegram của riêng bạn")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

            SettingsDivider()

            SettingsRow(symbol: "info.circle", title: "Phiên bản") {
                SettingsValue(version)
            }

            SettingsDivider()

            SettingsRow(symbol: "number", title: "Bản build") {
                SettingsValue(AppVersion.build)
            }
        }
    }

    private var updateCard: some View {
        SettingsCard(title: "Cập nhật") {
            SettingsRow(symbol: "doc.text", title: "Nhật ký cập nhật",
                        subtitle: "Doni \(version)",
                        action: { showsNotes = true }) {
                Chevron()
            }

            SettingsDivider()

            SettingsRow(symbol: "arrow.triangle.2.circlepath",
                        title: "Tự động kiểm tra khi mở app") {
                DesktopUpdateCheckToggle()
            }

            SettingsDivider()

            SettingsRow(symbol: "arrow.triangle.2.circlepath",
                        title: isChecking ? "Đang kiểm tra…" : "Kiểm tra cập nhật",
                        action: check) {
                if isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Chevron()
                }
            }
        }
    }

    private var aboutCard: some View {
        SettingsCard(title: "Về Doni") {
            paragraph("Doni viết bằng SwiftUI thuần và phát nhạc từ các kênh Telegram cùng Saved Messages của chính bạn, qua TDLib. Không có máy chủ nào của riêng app, không có tài khoản nào ngoài tài khoản Telegram của bạn, và không có gì được gửi đi ngoài Telegram và các nguồn lời bài hát.")
        }
    }

    private var copyrightCard: some View {
        SettingsCard(title: "Bản quyền") {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: AppAbout.copyright)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            SettingsDivider()

            SettingsRow(symbol: "chevron.left.forwardslash.chevron.right",
                        title: "Kho GitHub",
                        action: { openURL(AppUpdateService.repositoryURL) }) {
                Chevron()
            }

            SettingsDivider()

            Button {
                openURL(AppAbout.telegramURL)
            } label: {
                HStack(spacing: 12) {
                    Image("TelegramMark")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Telegram")
                            .font(.system(size: 13.5, weight: .medium))
                        Text(verbatim: AppAbout.telegramHandle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 10)

                    Chevron()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 54, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var licensesCard: some View {
        SettingsCard(title: "Mã nguồn mở & Giấy phép") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(AppAbout.licences.enumerated()), id: \.element.id) { index, part in
                    if index > 0 { SettingsDivider() }
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: part.name)
                            .font(.system(size: 13.5, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(verbatim: part.licence)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
            }
        }
    }

    private var disclaimerCard: some View {
        SettingsCard(title: "Miễn trừ trách nhiệm") {
            paragraph("Doni là ứng dụng không chính thức, không liên kết và không được Telegram hay bất kỳ hãng nhạc nào uỷ quyền. Nó chỉ mở những file đang nằm trong tài khoản Telegram của bạn.")
                .foregroundStyle(.secondary)
        }
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.leading, 6)
            .padding(.top, -14)
    }

    private func check() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { Task { @MainActor in isChecking = false } }
            do {
                let result = try await AppUpdateService.check()
                await MainActor.run {
                    alert = result.hasUpdate
                        ? .available(result, version: version)
                        : .current(version: version)
                }
            } catch {
                await MainActor.run { alert = .failed(error) }
            }
        }
    }
}

/// The notes this build shipped with, lifted into a sheet because the desktop's panel has no stack
/// to push them onto.
struct DesktopReleaseNotesSheet: View {
    let notes: AppReleaseNotes
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if notes.entries.isEmpty {
                    ContentUnavailableView("Chưa có nhật ký cập nhật", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nội dung mới")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(notes.entries.enumerated()), id: \.offset) { _, entry in
                            // The loader already picked these lines' language, so they are data, not keys.
                            Text(verbatim: entry)
                                .font(.system(size: 13))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
            }

            Divider()

            HStack {
                Text(verbatim: "Doni \(notes.version)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

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
        .frame(width: 480, height: 520)
    }
}
