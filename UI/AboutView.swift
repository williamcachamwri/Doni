import SwiftUI
import TelegramDesignSystem

/// The About screen, shaped on `MeloX/Features/Settings/Application/AboutView.swift`: build version,
/// updates, release notes, author, licences. Contact is GitHub plus the Telegram account that signs
/// the builds — there is no website and no community group.
struct AboutView: View {
    @Environment(\.openURL) private var openURL

    @State private var notes = AppReleaseNotes.load()
    @State private var checksOnLaunch = AppUpdateSettings.checksOnLaunch
    @State private var isChecking = false
    @State private var alert: UpdateAlert?

    private var version: String { AppVersion.displayName(AppVersion.current) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .center, spacing: 10) {
                    DoniLogo(side: 72)
                    Text("Doni").font(.title2.bold())
                    Text("Máy nghe nhạc Telegram của riêng bạn")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Thông tin ứng dụng") {
                LabeledContent("Phiên bản", value: version)
                LabeledContent("Bản build", value: AppVersion.build)
            }

            Section {
                NavigationLink {
                    ReleaseNotesView(notes: notes)
                } label: {
                    LabeledContent("Nhật ký cập nhật") {
                        Text(verbatim: "Doni \(version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Tự động kiểm tra khi mở app", isOn: $checksOnLaunch)
                    .onChange(of: checksOnLaunch) { _, on in
                        AppUpdateSettings.checksOnLaunch = on
                    }
                Button {
                    check()
                } label: {
                    HStack {
                        Label(isChecking ? "Đang kiểm tra…" : "Kiểm tra cập nhật",
                              systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if isChecking { ProgressView() }
                    }
                }
                .disabled(isChecking)
            } header: {
                Text("Cập nhật")
            } footer: {
                Text("Tự động kiểm tra chỉ báo khi có bản mới; kiểm tra hỏng thì im lặng.")
            }

            Section("Về Doni") {
                Text("Doni viết bằng SwiftUI thuần và phát nhạc từ các kênh Telegram cùng Saved Messages của chính bạn, qua TDLib. Không có máy chủ nào của riêng app, không có tài khoản nào ngoài tài khoản Telegram của bạn, và không có gì được gửi đi ngoài Telegram và các nguồn lời bài hát.")
            }

            Section("Bản quyền") {
                Text("© 2026 williamcachamwri")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    openURL(AppUpdateService.repositoryURL)
                } label: {
                    Label("Kho GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button {
                    openURL(Self.telegramURL)
                } label: {
                    HStack(spacing: 12) {
                        // Telegram's own mark, unmodified, from the icon file the project ships: the
                        // row says where the music lives, and a generic paper plane would say
                        // something else.
                        Image("TelegramMark")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        LabeledContent("Telegram") {
                            Text(verbatim: "@williamcachamwri")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    LicensesView()
                } label: {
                    Label("Dự án & Giấy phép", systemImage: "doc.text")
                }
            } header: {
                Text("Mã nguồn mở & Giấy phép")
            } footer: {
                Text("Doni đứng trên vai TDLib, OpenSSL và mã của MeloX; giấy phép của từng thứ được ghi ở đây.")
            }

            Section("Miễn trừ trách nhiệm") {
                Text("Doni là ứng dụng không chính thức, không liên kết và không được Telegram hay bất kỳ hãng nhạc nào uỷ quyền. Nó chỉ mở những file đang nằm trong tài khoản Telegram của bạn.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Giới thiệu Doni")
        .navigationBarTitleDisplayMode(.inline)
        .updateAlert($alert)
    }

    private static let telegramURL = URL(string: "https://t.me/w1lliamcachamwri")!

    private func check() {
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

/// The notes this build shipped with.
struct ReleaseNotesView: View {
    let notes: AppReleaseNotes

    var body: some View {
        List {
            if notes.entries.isEmpty {
                ContentUnavailableView("Chưa có nhật ký cập nhật", systemImage: "doc.text")
            } else {
                Section {
                    ForEach(Array(notes.entries.enumerated()), id: \.offset) { _, entry in
                        // The loader already picked these lines' language, so they are data, not keys.
                        Text(verbatim: entry)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Nội dung mới")
                } footer: {
                    Text(verbatim: "Doni \(notes.version)")
                }
            }
        }
        .navigationTitle("Nhật ký cập nhật")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What Doni is built out of, and each part's licence. Doni is GPL-3.0 because the lyrics screen and
/// several feed views came from GPLv3 MeloX; TDLib and OpenSSL are linked, Telegram-iOS was only
/// measured, and the lyrics sources are web requests rather than code.
struct LicensesView: View {
    private struct Part: Identifiable {
        let name: String
        let licence: String
        var id: String { name }
    }

    private let parts: [Part] = [
        Part(name: "Doni", licence: "GPL-3.0"),
        Part(name: "TDLib", licence: "Boost Software License 1.0"),
        Part(name: "OpenSSL", licence: "Apache-2.0"),
        Part(name: "SQLite", licence: "Public domain"),
        Part(name: "MeloX", licence: "GPL-3.0"),
        Part(name: "Telegram-iOS", licence: "GPL-2.0"),
        Part(name: "lrclib · NetEase · AMLL · QQ Music", licence: "Web API"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(parts) { part in
                    HStack(alignment: .firstTextBaseline) {
                        // Project names and their authors' licence strings are other people's
                        // words, not table keys.
                        Text(verbatim: part.name).font(.body.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(verbatim: part.licence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Bản đầy đủ của GPL-3.0 nằm trong file LICENSE của kho mã.")
            }
        }
        .navigationTitle("Dự án & Giấy phép")
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// The app's own mark: the home-screen icon, at whatever side a surface draws it.
///
/// The corner radius is 22.5 % of the side, which is the proportion of the iOS icon mask itself, so
/// this tile and the real icon on the springboard are the same shape rather than two different ones.
struct DoniLogo: View {
    var side: CGFloat = 72

    var body: some View {
        Image("DoniMark")
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
            .accessibilityLabel("Doni")
    }
}
