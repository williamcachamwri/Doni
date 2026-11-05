import SwiftUI
import TelegramDesignSystem
import TdSession

/// The channel allow-list: probe a link before the app reads a whole channel, or pick from chats the
/// account is already in.
///
/// TDLib never reports a channel's total song count — `getChatHistory` only hands over pages
/// (`td_api.tl:12758`) — so the probe counts one page and reports "≈38 bài trong 100 tin gần nhất".
/// Joined channels skip the probe: the account already knows what they hold, and the walk is the same
/// request for channel, group, person and bot.
struct AddChannelSheet: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var library: Library
    /// Caller's post-add hook: indexing starts straight away, not at the next Library refresh.
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var isProbing = false
    @State private var probe: TdChannelProbe?
    @State private var failure: String?
    @State private var joined: [TdChannel] = []
    @State private var isListingJoined = false
    @State private var joinedFailure: String?
    /// The account's whole chat list, which can run to hundreds of rows — hence the filter.
    @State private var query = ""

    /// Reference song-row gaps: 12 mark-to-text, 3 line-to-line
    /// (`Shared/Media/TrackRowView.swift:3-197`).
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

    /// Every query word must appear in the row's name or handle — the settings screen's filter rule.
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

    /// The probe's answer and its add button.
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

    /// Telegram's own word per chat kind — the list holds groups, people and bots, not just channels.
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
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.glassProminent)
                .fixedSize(horizontal: true, vertical: false)
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

    /// Resolve the handle, then count one page of it. A failure is shown as a message, not a state:
    /// the only fix is a different handle.
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
            // "No chats" and "could not read the chat list" are different sentences.
            joinedFailure = LibraryIndexer.describe(error)
        }
    }
}

/// Empty-library prompt: one prominent button to add a channel. Handed out by both Home segments.
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
