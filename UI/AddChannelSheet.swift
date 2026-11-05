import SwiftUI
import TelegramDesignSystem
import TdSession

/// The screen the channel allow-list grows from: paste a channel's link and see what is in it
/// before the app agrees to read all of it, or take one out of the channels this account is
/// already in.
///
/// The probe is the reason this is a screen and not a text field. TDLib will not say how many
/// songs a channel has ever posted — `getChatHistory` only hands over pages (`td_api.tl:12758`) —
/// so the honest number is the one a single page can count, "≈38 bài trong 100 tin gần nhất". A
/// walk that turns out to have been started on a channel of pictures is a walk of thousands of
/// round trips wasted.
///
/// A channel picked from the joined list is added without a probe: the account is in it, so the
/// user already knows what it holds, and a probe costs a page of history for one candidate where
/// the list costs one request for all of them. The list is every chat the account is in — channel,
/// group, person, bot — because the walk that follows is the same request for all four.
struct AddChannelSheet: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var library: Library
    /// What the screen that opened this asks for after an add: the walk starts straight away,
    /// because a channel on the list but not yet read is a channel that is not on the list.
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var isProbing = false
    @State private var probe: TdChannelProbe?
    @State private var failure: String?
    @State private var joined: [TdChannel] = []
    @State private var isListingJoined = false
    @State private var joinedFailure: String?
    /// The chat list is the account's whole list, which on a busy account is hundreds of rows, so it
    /// gets a filter rather than a scroll.
    @State private var query = ""

    /// The rows take the reference's song row: 12 between the mark and the text, 3 between the two
    /// lines (`Shared/Media/TrackRowView.swift:3-197`).
    private static let rowGap: CGFloat = 12
    private static let textGap: CGFloat = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("t.me/kenhnhac hoặc @kenhnhac", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(probeLink)

                    if isProbing {
                        HStack(spacing: Self.rowGap) {
                            ProgressView()
                            Text("Đang đọc 100 tin gần nhất…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let probe {
                        probeRow(probe)
                    } else if let failure {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Kênh mới")
                } footer: {
                    Text("Doni chỉ lấy những bài audio, dù nguồn là kênh, nhóm, người dùng hay bot.")
                }

                Section {
                    if isListingJoined {
                        HStack(spacing: Self.rowGap) {
                            ProgressView()
                            Text("Đang mở danh sách trò chuyện…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let joinedFailure {
                        Text(joinedFailure)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if visibleJoined.isEmpty {
                        Text(joined.isEmpty
                             ? "Không có cuộc trò chuyện nào."
                             : localized("Không có cuộc trò chuyện nào khớp “%@”.",
                                query.trimmingCharacters(in: .whitespaces)))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleJoined, id: \.chatId) { channel in
                            joinedRow(channel)
                        }
                    }
                } header: {
                    Text("Cuộc trò chuyện bạn đang tham gia")
                }
            }
            .formStyle(.grouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Tìm cuộc trò chuyện")
            .navigationTitle("Thêm kênh nhạc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await listJoined() }
    }

    // MARK: Filter

    /// The chat list under the query — every word has to turn up in the row's own name or handle,
    /// which is the rule the settings screen filters its rows by too.
    private var visibleJoined: [TdChannel] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return joined }
        return joined.filter { channel in
            let text = "\(channel.title) @\(channel.username)".lowercased()
            return words.allSatisfy(text.contains)
        }
    }

    // MARK: Rows

    /// The probe's answer and the only button on the screen: what is in the channel, and whether to
    /// read it.
    private func probeRow(_ probe: TdChannelProbe) -> some View {
        HStack(spacing: Self.rowGap) {
            channelTitle(probe.channel,
                         subtitle: probe.trackCount == 0
                             ? localized("Không có bài audio nào trong %@ tin gần nhất", probe.messageCount.formatted())
                             : localized("≈%@ bài trong %@ tin gần nhất",
                                 probe.trackCount.formatted(), probe.messageCount.formatted()))
            Spacer(minLength: 8)
            addButton(for: probe.channel)
        }
    }

    private func joinedRow(_ channel: TdChannel) -> some View {
        HStack(spacing: Self.rowGap) {
            channelTitle(channel, subtitle: Self.kindLabel(channel.kind))
            Spacer(minLength: 8)
            addButton(for: channel)
        }
    }

    /// Telegram's own word for each kind of chat, because the list is no longer only channels and a
    /// person's chat row has to say so.
    private static func kindLabel(_ kind: TdChannel.Kind) -> String {
        switch kind {
        case .channel: "Kênh"
        case .group: "Nhóm"
        case .user: "Người dùng"
        case .bot: "Bot"
        }
    }

    private func channelTitle(_ channel: TdChannel, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: Self.textGap) {
            Text(channel.title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .layoutPriority(1)
    }

    /// Already on the list is not an error, so the row says it instead of offering a second add.
    private func addButton(for channel: TdChannel) -> some View {
        Group {
            if isOnList(channel) {
                Label("Đã thêm", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Đã thêm vào danh sách")
            } else {
                Button {
                    add(channel)
                } label: {
                    Text("Thêm")
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel(localized("Thêm %@", channel.title))
            }
        }
    }

    // MARK: Actions

    private func add(_ channel: TdChannel) {
        library.add(channel)
        onAdd()
        dismiss()
    }

    private func isOnList(_ channel: TdChannel) -> Bool {
        library.channels.contains { $0.chatId == channel.chatId }
    }

    /// Resolve the handle, then count one page of it. Both are the reader's own requests; a failure
    /// in either is a message rather than a state, because the only fix is a different handle.
    private func probeLink() {
        let text = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProbing else { return }
        guard let reader = session.reader() else { return }
        probe = nil
        failure = nil
        isProbing = true
        Task {
            defer { isProbing = false }
            do {
                probe = try await reader.probe(await reader.channel(username: text))
            } catch {
                failure = LibraryIndexer.describe(error)
            }
        }
    }

    private func listJoined() async {
        guard let reader = session.reader() else { return }
        isListingJoined = true
        defer { isListingJoined = false }
        do {
            joined = try await reader.channels()
        } catch {
            // An empty list and a list that could not be read are different sentences, and the one
            // that was wrong here said "you are in no chats".
            joinedFailure = LibraryIndexer.describe(error)
        }
    }
}

/// The one thing a library with no songs can ask for: a channel to read.
///
/// Drawn as a button the finger can see rather than a line of grey text that happens to be tappable,
/// because it is the only door on the screen — the account's own chat list, a link to probe, and a
/// search over both. Both of the Home tab's segments hand out this one.
struct AddChannelPrompt: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 38, weight: .thin))
                .foregroundStyle(.tertiary)

            Text(LocalizedStringKey(title))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Button(action: action) {
                Label("Thêm kênh nhạc", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(MusicTint.accent)
            .padding(.top, 6)

            Text("Chọn từ danh sách trò chuyện Telegram, hoặc dán link kênh, nhóm, bot, chat riêng.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
    }
}
