import SwiftUI
import Support
import TelegramDesignSystem

/// What is on the phone, and the one button that takes it away — in MeloX's settings cards:
/// a `VStack(spacing: 32)` on the grouped background, each card a 26 pt continuous rectangle of
/// `secondarySystemGroupedBackground` under a `.headline` in `.secondary`, each row a 30 pt tinted
/// glyph, a `body.weight(.semibold)` title and a `caption` line under it, 18 × 13 pt of padding in a
/// 68 pt minimum height, separated by a divider that starts 58 pt in
/// (`SettingsHomeComponents.swift:19-92`, `SettingsView.swift:26-41`).
///
/// MeloX's `.searchable` on this screen filters fourteen destinations; Doni has three cards, so the
/// field would search a list shorter than the field's own prompt and it is left off.
///
/// Logout is the screen's reason to exist. `file_id` is TDLib's number inside its own database
/// (`td_api.tl:326`), so rows written against one session point at nothing once another starts —
/// the library goes with the session rather than being left behind to fail.
struct SettingsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var library: Library

    @State private var confirmingLogout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MusicSettingsMetrics.sectionSpacing) {
                card("Thư viện") {
                    row("doc.text", "Bài đã chỉ mục",
                        value: library.trackCount.formatted())
                    divider
                    row("arrow.down.circle", "Đã tải về máy",
                        value: "\(library.downloadedCount.formatted()) bài")
                    divider
                    row("internalfolder", "Dung lượng đã tải",
                        value: DataSize.string(library.downloadedBytes))
                }

                card("Kênh nhạc") {
                    if library.channels.isEmpty {
                        row("antenna.radiowaves.left.and.right", "Chưa thêm kênh nào")
                    } else {
                        ForEach(library.channels) { channel in
                            if channel.id != library.channels.first?.id { divider }
                            row("person.2", channel.title,
                                subtitle: channel.username.isEmpty ? nil : "@\(channel.username)",
                                selected: channel.isSelected) {
                                library.select(channel: channel.chatId)
                            }
                        }
                    }
                }

                signOutCard
            }
            .padding(.horizontal, MusicSettingsMetrics.sidePadding)
            .padding(.top, MusicSettingsMetrics.contentTop)
            .padding(.bottom, MusicSettingsMetrics.contentBottom)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Đăng xuất khỏi Telegram?", isPresented: $confirmingLogout,
                            titleVisibility: .visible) {
            Button("Đăng xuất", role: .destructive) { signOut() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Thư viện, các bài đã yêu thích và danh sách phát trên máy sẽ bị xoá. "
                + "Phiên đăng nhập sẽ bị đóng.")
        }
    }

    // MARK: Cards

    /// A card is its header's `.headline` and one filled box 10 pt under it
    /// (`SettingsHomeComponents.swift:23-51`).
    private func card<Content: View>(_ title: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MusicSettingsMetrics.headerToCard) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, MusicSettingsMetrics.headerPadding)
            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: MusicSettingsMetrics.cardRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
    }

    private var divider: some View {
        Divider().padding(.leading, MusicSettingsMetrics.dividerLeading)
    }

    /// One row: the tinted glyph in its 30 pt column, the words beside it, and either a value or a
    /// mark on the right (`SettingsHomeComponents.swift:58-88`).
    private func row(_ symbol: String, _ title: String, subtitle: String? = nil,
                     value: String? = nil, selected: Bool = false,
                     action: (() -> Void)? = nil) -> some View {
        let content = HStack(spacing: MusicSettingsMetrics.rowIconGap) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: MusicSettingsMetrics.rowIconWidth)
            VStack(alignment: .leading, spacing: MusicSettingsMetrics.rowTextGap) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(MusicSettingsMetrics.chevronFont)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, MusicSettingsMetrics.rowPaddingH)
        .padding(.vertical, MusicSettingsMetrics.rowPaddingV)
        .frame(minHeight: MusicSettingsMetrics.rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)

        return Group {
            if let action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    /// The reset card MeloX puts at the foot of the screen: the destructive row in its own box, and
    /// the consequence spelled out under it (`SettingsHomeComponents.swift:94-145`).
    private var signOutCard: some View {
        VStack(alignment: .leading, spacing: MusicSettingsMetrics.headerToCard) {
            Text("Tài khoản")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, MusicSettingsMetrics.headerPadding)
            Button(role: .destructive, action: { confirmingLogout = true }) {
                HStack(spacing: MusicSettingsMetrics.rowIconGap) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.title3.weight(.medium))
                        .frame(width: MusicSettingsMetrics.rowIconWidth)
                    Text("Đăng xuất")
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, MusicSettingsMetrics.rowPaddingH)
                .padding(.vertical, MusicSettingsMetrics.rowPaddingV)
                .frame(minHeight: MusicSettingsMetrics.rowMinHeight)
                .contentShape(.rect)
                .background {
                    RoundedRectangle(cornerRadius: MusicSettingsMetrics.cardRadius, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                }
            }
            .buttonStyle(.plain)
            Text("Xoá thư viện trên máy và đóng phiên đăng nhập. Đã tải về sẽ mất; kênh vẫn còn trên Telegram.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, MusicSettingsMetrics.headerPadding)
        }
    }

    /// The rows go first, then the session: a database emptied under a live client would be read
    /// back into memory by whatever is still walking a channel.
    private func signOut() {
        library.wipe()
        session.logOut()
    }
}

#Preview {
    NavigationStack {
        SettingsView(session: TelegramSession(), library: Library.shared)
    }
}
