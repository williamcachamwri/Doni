import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The screen MeloX builds its settings root out of: a `VStack(spacing: 32)` of cards on
/// `systemGroupedBackground`, 16 pt on the sides, 14 above and 88 below, the app's mark in the
/// navigation bar's principal slot and a search field under it that prunes the cards
/// (`SettingsView.swift:27-45`, `:38`).
///
/// Every card is a `.headline` in `.secondary` over one 26 pt continuous rectangle of
/// `secondarySystemGroupedBackground`; every row in it is a 30 pt tinted glyph, a
/// `body.weight(.semibold)` title with a `caption` line under it and 18 × 13 pt of padding in a 68 pt
/// minimum height, separated by a divider that starts 58 pt in (`SettingsHomeComponents.swift:19-92`).
///
/// First on the screen is the account block — the identity card and, 32 pt under it, the red
/// sign-out, neither of them carrying a header (`SettingsAccountSection.swift:17-31`, `:142-153`,
/// `:163-196`). The round things here are the marks that stand for somebody rather than for a cover:
/// the account mark, which is MeloX's own (`SettingsAccountSection.swift:213-214`), and the photo each
/// channel wears in the list below. The rule that made every artwork a rounded square never reaches
/// them.
///
/// The search field is the reference's behaviour, not its decoration: a query is split on whitespace
/// and a row survives only when every piece of it turns up in that row's own text, and a card with
/// nothing left in it goes away (`SettingsCatalog.swift:120-148`, `SettingsView.swift:99-106`).
///
/// Logout is the screen's reason to exist. `file_id` is TDLib's number inside its own database
/// (`td_api.tl:326`), so rows written against one session point at nothing once another starts —
/// the library goes with the session rather than being left behind to fail.
struct SettingsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var indexer: LibraryIndexer
    @ObservedObject var player: Player
    @ObservedObject var library: Library

    @State private var confirmingLogout = false
    @State private var searchText = ""
    @State private var showsAddChannel = false
    @State private var showsPendingSongs = false
    @State private var showsStorage = false

    var body: some View {
        ScrollView {
            VStack(spacing: MusicSettingsMetrics.sectionSpacing) {
                if showsAccount {
                    accountCard
                    if session.isAuthorized { logoutCard }
                }

                if !lines.isEmpty {
                    card("Thư viện") {
                        ForEach(lines) { line in
                            if line.id != lines.first?.id { divider }
                            row(line.symbol, line.title,
                                subtitle: line.subtitle, value: line.value,
                                action: line.action)
                        }
                    }
                }

                if showsChannels {
                    card("Kênh nhạc", accessory: {
                        Button("Thêm") { showsAddChannel = true }
                            .buttonStyle(.glass)
                    }) {
                        if visibleChannels.isEmpty {
                            row("antenna.radiowaves.left.and.right", "Chưa thêm kênh nào")
                        } else {
                            ForEach(visibleChannels) { channel in
                                if channel.id != visibleChannels.first?.id { divider }
                                row(channel.title, mark: {
                                    ChannelAvatar(channel: channel, library: library,
                                                  session: session)
                                }, subtitle: subtitle(for: channel),
                                  selected: channel.isIndexed) {
                                    library.setIndexed(channel.chatId, on: !channel.isIndexed)
                                    indexer.run(session, library: library)
                                }
                            }
                        }
                    }
                }

                if !showsAccount && lines.isEmpty && !showsChannels {
                    ContentUnavailableView("Không tìm thấy", systemImage: "magnifyingglass",
                                           description: Text("Thử từ khoá khác."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                }
            }
            .padding(.horizontal, MusicSettingsMetrics.sidePadding)
            .padding(.top, MusicSettingsMetrics.contentTop)
            .padding(.bottom, MusicSettingsMetrics.contentBottom)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Doni")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Tìm kiếm cài đặt")
        .toolbar {
            ToolbarItem(placement: .principal) { brandMark }
        }
        .confirmationDialog("Đăng xuất khỏi Telegram?", isPresented: $confirmingLogout,
                            titleVisibility: .visible) {
            Button("Đăng xuất", role: .destructive) { signOut() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Thư viện, các bài đã yêu thích và danh sách phát trên máy sẽ bị xoá. "
                + "Phiên đăng nhập sẽ bị đóng.")
        }
        .sheet(isPresented: $showsAddChannel) {
            AddChannelSheet(session: session, library: library) {
                indexer.run(session, library: library)
            }
        }
        .navigationDestination(isPresented: $showsPendingSongs) {
            // The cover cache the app already holds: the rows on that screen are the songs the phone
            // does not have yet, and their pictures come through the same cache as every other row.
            PendingSongsView(session: session, player: player, artwork: CoverArtwork.shared,
                             library: library, indexer: indexer)
        }
        .navigationDestination(isPresented: $showsStorage) {
            StorageView(session: session, player: player, artwork: CoverArtwork.shared,
                        library: library)
        }
        // The card's storage line quotes the disk, not the rows, so the walk is asked for on the way
        // in. It runs detached at utility priority and a second visit costs nothing the first missed.
        .task { await library.remeasureDisk() }
    }

    // MARK: Header

    /// The reference's title is the app's mark — 28 pt at a 7 pt clip, 8 from a `.headline` name
    /// (`SettingsHomeComponents.swift:5-14`). Doni ships no asset catalog, so the mark is drawn from
    /// the accent in the same box rather than left out.
    private var brandMark: some View {
        HStack(spacing: MusicSettingsMetrics.logoGap) {
            RoundedRectangle(cornerRadius: MusicSettingsMetrics.logoRadius, style: .continuous)
                .fill(MusicTint.accent)
                .frame(width: MusicSettingsMetrics.logoSide,
                       height: MusicSettingsMetrics.logoSide)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
            Text("Doni")
                .font(.headline)
        }
    }

    // MARK: Account

    /// A 60 pt mark, the name in `.title3.weight(.semibold)` on one line and a `.subheadline` in
    /// `.secondary` on two under it, in 18 × 16 of padding on a 100 pt minimum height at radius 28
    /// (`SettingsAccountSection.swift:64-76`, `:142-153`). While `getMe` is still in flight the card
    /// wears the reference's loading branch (`:91-99`).
    private var accountCard: some View {
        Group {
            if let account = session.account {
                HStack(spacing: MusicSettingsMetrics.accountGap) {
                    AccountAvatar(account: account, photo: session.accountPhoto,
                                  side: MusicSettingsMetrics.accountAvatar)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: MusicSettingsMetrics.accountTextGap) {
                        Text(account.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(detail(account))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)
                }
            } else {
                HStack(spacing: MusicSettingsMetrics.accountGap) {
                    ProgressView()
                        .frame(width: MusicSettingsMetrics.accountAvatar,
                               height: MusicSettingsMetrics.accountAvatar)
                    VStack(alignment: .leading, spacing: MusicSettingsMetrics.accountTextGap) {
                        Text("Tài khoản Telegram")
                            .font(.title3.weight(.semibold))
                        Text("Đang đọc thông tin…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, MusicSettingsMetrics.accountPaddingH)
        .padding(.vertical, MusicSettingsMetrics.accountPaddingV)
        .frame(maxWidth: .infinity, minHeight: MusicSettingsMetrics.accountMinHeight,
               alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: MusicSettingsMetrics.accountRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    /// The reference puts the account's own number under its name; Doni also has the handle its
    /// channels are read by, so that comes first.
    private func detail(_ account: TdAccount) -> String {
        account.username.isEmpty ? "ID \(account.id)" : "@\(account.username) · ID \(account.id)"
    }

    /// Sign-out, in the account section's own card: no header and no footnote, the whole label in
    /// red, a 30 pt glyph 14 from a `.body.weight(.medium)` title in 18 × 14 of padding 60 pt tall
    /// at the usual 26 pt radius (`SettingsAccountSection.swift:163-196`).
    private var logoutCard: some View {
        Button(role: .destructive) { confirmingLogout = true } label: {
            HStack(spacing: MusicSettingsMetrics.rowIconGap) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title3.weight(.medium))
                    .frame(width: MusicSettingsMetrics.rowIconWidth)
                Text("Đăng xuất")
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MusicSettingsMetrics.rowPaddingH)
            .padding(.vertical, MusicSettingsMetrics.logoutPaddingV)
            .frame(minHeight: MusicSettingsMetrics.logoutMinHeight)
            .contentShape(.rect)
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: MusicSettingsMetrics.cardRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    // MARK: Cards

    /// A card is its header's `.headline` and one filled box 10 pt under it
    /// (`SettingsHomeComponents.swift:23-51`).
    private func card<Content: View>(_ title: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        card(title, accessory: { EmptyView() }, content: content)
    }

    /// The same card with one thing at the right edge of its header, which is where a list you add
    /// to wants its add.
    private func card<Accessory: View, Content: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MusicSettingsMetrics.headerToCard) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                accessory()
            }
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
        row(title, mark: {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(.tint)
        }, subtitle: subtitle, value: value, selected: selected, action: action)
    }

    /// The same row with a mark of the caller's own rather than a glyph, which is what lets a channel
    /// wear its Telegram photo in the column the placeholder used to fill.
    private func row<Mark: View>(_ title: String,
                                 @ViewBuilder mark: () -> Mark,
                                 subtitle: String? = nil, value: String? = nil,
                                 selected: Bool = false,
                                 action: (() -> Void)? = nil) -> some View {
        let content = HStack(spacing: MusicSettingsMetrics.rowIconGap) {
            mark()
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

    // MARK: What is on the phone

    /// The library's numbers, in the two-line shape every other row on the screen wears. The first
    /// two carry a value and nowhere to go; the last two each have a screen of their own, because a
    /// song waiting to be fetched is a queue and a queue wants rows, and because bytes that have to
    /// be counted off the disk want a screen that can throw them away.
    private var lines: [SettingLine] {
        [
            SettingLine(symbol: "doc.text", title: "Bài đã chỉ mục",
                        subtitle: "Lấy từ các kênh đã chọn",
                        value: library.trackCount.formatted(),
                        keywords: "thư viện nhạc bài hát index"),
            SettingLine(symbol: "arrow.down.circle", title: "Đã tải về máy",
                        subtitle: "Nghe được khi không có mạng",
                        value: "\(library.downloadedCount.formatted()) bài",
                        keywords: "tải offline file"),
            SettingLine(symbol: "internalfolder", title: "Bộ nhớ",
                        subtitle: "Ảnh bìa, nhạc Telegram, file của bạn",
                        value: library.disk.map { DataSize.string($0.managedBytes) } ?? "…",
                        keywords: "dung lượng bộ nhớ cache storage disk",
                        action: { showsStorage = true }),
            SettingLine(symbol: "tray.and.arrow.down", title: "Bài chưa tải về",
                        subtitle: "Chọn bài để đưa về máy",
                        value: pendingCount.formatted(),
                        keywords: "cloud chưa tải chờ download telegram",
                        action: { showsPendingSongs = true }),
        ].filter { $0.matches(searchText) }
    }

    /// The songs the channels hold and the phone does not. Read off the rows the library already
    /// publishes — the same list the pending screen filters — rather than a new store query for one
    /// number. A file the user imported is not in it: nothing can fetch such a song back.
    private var pendingCount: Int {
        library.storedTracks.reduce(0) { $1.isDownloaded || $1.isLocal ? $0 : $0 + 1 }
    }

    private var visibleChannels: [StoreChannel] {
        library.channels.filter {
            SettingsSearch.matches(searchText,
                                   in: [$0.title, $0.username, "kênh channel nhạc"])
        }
    }

    /// The handle the channel was added by and how many of its songs are on the phone. A channel
    /// picked out of the joined list came in by its chat id, so the count is all it can say.
    private func subtitle(for channel: StoreChannel) -> String {
        let songs = "\(library.store.trackCount(chatId: channel.chatId).formatted()) bài"
        let handle = channel.username.isEmpty ? nil : "@\(channel.username)"
        return [handle, songs].compactMap { $0 }.joined(separator: " · ")
    }

    /// The empty card stays while the field is blank and goes once something is typed into it: a row
    /// that says there are no channels is not an answer to a search.
    private var showsChannels: Bool {
        !visibleChannels.isEmpty || (library.channels.isEmpty
            && !SettingsSearch.isActive(searchText))
    }

    private var showsAccount: Bool {
        SettingsSearch.matches(searchText, in: ["tài khoản", "telegram", "đăng xuất", "hồ sơ",
                                                session.account?.name ?? "",
                                                session.account?.username ?? ""])
    }

    /// The rows go first, then the session: a database emptied under a live client would be read
    /// back into memory by whatever is still walking a channel.
    private func signOut() {
        library.wipe()
        session.logOut()
    }
}

/// One row of a card that carries a value instead of a chevron. `action` is the difference between
/// a number and a door: the rows that have one open a screen, and the ones that do not only say what
/// the library holds.
private struct SettingLine: Identifiable {
    let symbol: String
    let title: String
    let subtitle: String
    let value: String
    let keywords: String
    var action: (() -> Void)? = nil

    var id: String { title }

    func matches(_ query: String) -> Bool {
        SettingsSearch.matches(query, in: [title, subtitle, value, keywords])
    }
}

/// MeloX's filter: trim, lower-case, split on whitespace, and keep the row only when every piece
/// turns up somewhere in its text (`SettingsCatalog.swift:120-148`).
private enum SettingsSearch {
    static func matches(_ query: String, in values: [String]) -> Bool {
        let text = values.joined(separator: " ").lowercased()
        let words = words(query)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { text.contains($0) }
    }

    static func isActive(_ query: String) -> Bool {
        !words(query).isEmpty
    }

    private static func words(_ query: String) -> [Substring] {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
    }
}

/// A channel's own Telegram picture, in the mark column of its row: 30 pt because that is the column
/// every other row on this screen has (`SettingsHomeComponents.swift:58-88`), and round because it
/// stands for a chat rather than for a cover.
///
/// What is drawn is a file on the phone, not a request in flight: `chat.photo`'s `small` variant is a
/// 160×160 JPEG (`td_api.tl:784`, `:779`) — five times the pixels this mark is drawn at, which is the
/// difference between a photo and a smear — and `Library.loadAvatar` copies it into a directory this
/// app owns the first time the row appears. So a visit to this screen after the first one costs one
/// read and no round trip at all, which is what "cực nhanh" has to mean when the picture lives on a
/// server in Amsterdam.
private struct ChannelAvatar: View {
    let channel: StoreChannel
    @ObservedObject var library: Library
    /// Only used inside the task, which is where the asking happens; the row's own redraw comes from
    /// the library publishing its channels.
    let session: TelegramSession

    var body: some View {
        mark
            .task { await library.loadAvatar(of: channel, on: session) }
    }

    @ViewBuilder
    private var mark: some View {
        if let image = library.avatarImage(of: channel) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: MusicSettingsMetrics.rowIconWidth,
                       height: MusicSettingsMetrics.rowIconWidth)
                .background(.quaternary, in: .circle)
                .clipShape(.circle)
        } else {
            // Until the bytes arrive, the row wears what it wore before it had a picture at all.
            Image(systemName: "person.2")
                .font(.title3.weight(.medium))
                .foregroundStyle(.tint)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(session: TelegramSession(), indexer: LibraryIndexer(),
                     player: Player(), library: Library.shared)
    }
}
