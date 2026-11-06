import Support
import SwiftUI
import TelegramDesignSystem

/// The account's own mark, at whatever size a surface draws it: the Telegram picture when there is one,
/// the name's first letter when there is not — a person, not a song, so no note glyph and no gradient
/// square. The sidebar's footer, this sheet and the settings window all wear this one thing.
struct DesktopAccountMark: View {
    @EnvironmentObject private var session: TelegramSession
    let size: CGFloat

    var body: some View {
        Group {
            if let photo = session.accountPhoto {
                Image(doni: photo)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle().fill(MusicTint.accent.gradient)
                    Text(session.account?.name.first.map { String($0).uppercased() } ?? "?")
                        .font(.system(size: max(11, size * 0.45), weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The panel the sidebar's footer opens — the reference's account sheet (`DesktopSidebar.swift:145-147`
/// opens `DesktopAccountView`), in the size and with the facts this app actually has: whose Telegram it
/// is, how much of it Doni has read, and the one button that gives all of it back.
struct DesktopAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var session: TelegramSession
    @EnvironmentObject private var library: Library
    @State private var confirmsLogout = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                DesktopAccountMark(size: 52)

                VStack(alignment: .leading, spacing: 3) {
                    name
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    if let account = session.account, !account.username.isEmpty {
                        Text("@\(account.username)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            counts
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack {
                Button("Huỷ") { dismiss() }
                Button("Đăng xuất", role: .destructive) { confirmsLogout = true }
            }
        }
        .padding(20)
        .frame(width: 340)
        .confirmationDialog("Đăng xuất khỏi Telegram?", isPresented: $confirmsLogout,
                            titleVisibility: .visible) {
            Button("Đăng xuất", role: .destructive) {
                dismiss()
                let account = model
                Task { await account.signOut() }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Toàn bộ thư viện, danh sách phát, nhạc đã tải về máy và cache ảnh bìa sẽ bị xoá. Phiên đăng nhập sẽ bị đóng.")
        }
    }

    private var name: Text {
        guard let account = session.account else { return Text("Chưa đăng nhập") }
        return Text(account.name)
    }

    /// What the listener is about to lose, in the same three numbers the panes count rows in.
    private var counts: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            count("Bài", library.trackCount)
            count("Kênh", library.channels.count)
            count("Danh sách", library.playlists.count)
        }
        .font(.system(size: 12.5))
    }

    /// `label` is a catalog key, so the lookup has to happen before `Text` sees it: a `String` handed to
    /// `Text` is drawn exactly as written.
    private func count(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(localized(label)).foregroundStyle(.secondary)
            Text(value.formatted()).gridColumnAlignment(.trailing)
        }
    }
}
