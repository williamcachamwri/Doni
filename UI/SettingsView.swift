import SwiftUI
import Support
import TelegramDesignSystem

/// What is on the phone, and the one button that takes it away.
///
/// The row is `ItemListUI`'s: a `scaled(17)` regular title — 17 pt at the app's own base —
/// 16 pt in, a `scaled(15)` value 20 pt from the right
/// edge, 15 pt of padding above and below (`Docs/design-tokens.md`, "Settings — the clothing the
/// item list wears"). Telegram sets these screens in rounded cards whose side margin comes from the
/// caller rather than from the module, so there is no number to read off it; Doni keeps the
/// full-bleed rows the rest of the shell already uses instead.
///
/// Logout is the screen's reason to exist. `file_id` is TDLib's number inside its own database
/// (`td_api.tl:326`), so rows written against one session point at nothing once another starts —
/// the library goes with the session rather than being left behind to fail.
struct SettingsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var library: Library

    @State private var confirmingLogout = false
    @Environment(\.telegramFloatingClearance) private var floatingClearance

    private let palette = TelegramPalette.dark

    var body: some View {
        ZStack(alignment: .top) {
            list
            GlassBar(title: "Cài đặt")
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .confirmationDialog("Đăng xuất khỏi Telegram?", isPresented: $confirmingLogout,
                            titleVisibility: .visible) {
            Button("Đăng xuất", role: .destructive) { signOut() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Thư viện, các bài đã yêu thích và danh sách phát trên máy sẽ bị xoá. Phiên đăng nhập sẽ bị đóng.")
        }
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                sectionTitle("Thư viện", first: true)
                SettingsRow(title: "Bài đã chỉ mục", value: library.trackCount.formatted())
                SettingsRow(title: "Đã tải về máy", value: "\(library.downloadedCount.formatted()) bài")
                SettingsRow(title: "Dung lượng đã tải", value: DataSize.string(library.downloadedBytes))

                sectionTitle("Kênh nhạc")
                if library.channels.isEmpty {
                    SettingsRow(title: "Chưa thêm kênh nào")
                } else {
                    ForEach(library.channels) { channel in
                        SettingsRow(title: channel.title,
                                    secondary: channel.username.isEmpty
                                        ? nil : "@\(channel.username)",
                                    value: channel.isSelected ? "Đang đọc" : nil) {
                            library.select(channel: channel.chatId)
                        }
                    }
                }

                sectionTitle("Phiên đăng nhập")
                SettingsRow(title: "Đăng xuất", destructive: true) {
                    confirmingLogout = true
                }
            }
            // A plain list closes its last section with 22 (`ItemListItem.swift:90`).
            .padding(.bottom, TelegramSettingsMetrics.plainSectionEnd)
        }
        .contentMargins(.top, TelegramBarMetrics.topClearance, for: .scrollContent)
        .contentMargins(.bottom, floatingClearance, for: .scrollContent)
    }

    /// 13 pt in `regular(13)`, 15 in from the edge, 7 down inside a band of its own text height plus
    /// 13 (`ItemListSectionHeaderItem.swift:183`, `:180`, `:252`, `:228`), and 24 above it when the
    /// list starts here, 28 once a section has ended above (`:229-233`). The colour is the
    /// reference's `sectionHeaderTextColor`, the grey the chat list's dates already wear
    /// (`DefaultDarkPresentationTheme.swift:430`).
    private func sectionTitle(_ text: String, first: Bool = false) -> some View {
        Text(text)
            .font(TelegramSettingsTypography.sectionHeader)
            .foregroundStyle(palette.chatListDateText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, TelegramSettingsMetrics.headerLeftInset)
            .padding(.top, (first
                ? TelegramSettingsMetrics.sectionGap
                : TelegramSettingsMetrics.sectionGapAfterSection)
                + TelegramSettingsMetrics.headerTitleY)
            .padding(.bottom, TelegramSettingsMetrics.headerBandPadding
                - TelegramSettingsMetrics.headerTitleY)
    }

    // MARK: Action

    /// The rows go first, then the session: a database emptied under a live client would be read
    /// back into memory by whatever is still walking a channel.
    private func signOut() {
        library.wipe()
        session.logOut()
    }
}

/// One row of the list.
///
/// A second line changes the row's own arithmetic, not just its content: the reference drops the
/// padding from 15 to 13 once a label sits under the title and separates the two lines by 1
/// (`ItemListDisclosureItem.swift:525-528`, `:546`). The value stays on the title's line either
/// way, because the reference right-aligns it against the block the title starts.
private struct SettingsRow: View {
    let title: String
    var secondary: String?
    var value: String?
    var destructive = false
    var action: (() -> Void)?

    @Environment(\.displayScale) private var displayScale

    private let palette = TelegramPalette.dark

    var body: some View {
        let content = HStack(alignment: secondary == nil ? .center : .top, spacing: 8) {
            VStack(alignment: .leading, spacing: TelegramSettingsMetrics.rowLineSpacing) {
                Text(title)
                    .font(TelegramSettingsTypography.rowTitle)
                    .foregroundStyle(destructive ? palette.listDestructive : palette.listPrimaryText)
                    .multilineTextAlignment(.leading)
                if let secondary {
                    Text(secondary)
                        .font(TelegramSettingsTypography.secondary)
                        .foregroundStyle(palette.listSecondaryText)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(TelegramSettingsTypography.value)
                    .foregroundStyle(palette.listSecondaryText)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.leading, TelegramSettingsMetrics.rowLeftInset)
        .padding(.trailing, TelegramSettingsMetrics.valueRightInset)
        .padding(.vertical, secondary == nil
            ? TelegramSettingsMetrics.rowVerticalInset
            : TelegramSettingsMetrics.rowVerticalInsetWithSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.chatListSeparator)
                .frame(height: TelegramGeometry.hairline(displayScale: displayScale))
                // The rule starts 16 in and runs to the edge: `bottomStripeNode` is framed from
                // `bottomStripeInset` to `params.width` (`ItemListActionItem.swift:253`, `:282`).
                .padding(.leading, TelegramSettingsMetrics.rowLeftInset)
        }

        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

#Preview {
    SettingsView(session: TelegramSession(), library: Library.shared)
}
