import SwiftUI
import Support
import TdSession
import TelegramDesignSystem

/// The two doors the phone's add-channel sheet has, in a Mac's shape: paste a handle, or pick one of
/// the chats this account already belongs to.
///
/// The verbs are the phone's and so is the order — resolve, count one page of it, then write it down —
/// because a channel that is in the list but never read is a channel the library does not have.
struct DesktopAddChannelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: TelegramSession
    let library: Library
    let onAdd: () -> Void

    @State private var handle = ""
    @State private var probe: TdChannelProbe?
    @State private var isProbing = false
    @State private var failure: String?
    @State private var joined: [TdChannel] = []
    @State private var showsJoined = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Thêm kênh")
                .font(.system(size: 15, weight: .semibold))

            HStack {
                TextField("t.me/kenhnhac hoặc @kenhnhac", text: $handle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(probeLink)
                    .disabled(isProbing)
                Button(isProbing ? "Đang kiểm tra…" : "Thêm", action: probeLink)
                    .keyboardShortcut(.defaultAction)
                    .disabled(handle.isEmpty || isProbing)
            }

            if let probe {
                result(probe.channel, subtitle: localized("%@ bài trong %@ tin",
                                                          probe.trackCount.formatted(),
                                                          probe.messageCount.formatted()),
                       add: { add(probe.channel) })
            }

            if let failure {
                Text(failure)
                    .font(.system(size: 11.5))
                    .foregroundStyle(MusicTint.accent)
            }

            Divider()

            HStack {
                Text("Trò chuyện đã tham gia")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(showsJoined ? "Ẩn" : "Xem") {
                    showsJoined = true
                    listJoined()
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }

            if showsJoined {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(joined, id: \.chatId) { channel in
                            result(channel,
                                   subtitle: Self.kindLabel(channel.kind),
                                   add: { add(channel) },
                                   added: library.channels.contains { $0.chatId == channel.chatId })
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder private func result(_ channel: TdChannel, subtitle: String,
                                     add: @escaping () -> Void, added: Bool = false) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(channel.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if added {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Đã thêm")
            } else {
                Button("Thêm", action: add)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    /// The phone's four words for the four things a chat can be (`UI/AddChannelSheet.swift:143-149`).
    private static func kindLabel(_ kind: TdChannel.Kind) -> String {
        switch kind {
        case .channel: return localized("Kênh")
        case .group: return localized("Nhóm")
        case .user: return localized("Người dùng")
        case .bot: return localized("Bot")
        }
    }

    /// Resolve, then count one page. A failure is shown as a message rather than a state: the only fix
    /// is a different handle.
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

    private func listJoined() {
        guard let reader = session.reader() else { return }
        Task {
            do {
                joined = try await reader.channels()
            } catch {
                failure = LibraryIndexer.describe(error)
            }
        }
    }

    private func add(_ channel: TdChannel) {
        library.add(channel)
        probe = nil
        handle = ""
        onAdd()
        dismiss()
    }
}

/// Search, the reference's way: the field is the pane, and what appears under it is songs — not
/// suggestions, not an empty room waiting for a keystroke.
struct DesktopSearchPane: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var indexer: LibraryIndexer
    @State private var query = ""

    var body: some View {
        let results = query.isEmpty ? DesktopPanes.all(model) : indexer.matches(of: query)
        return DesktopTrackPane(
            title: query.isEmpty ? localized("Tất cả bài hát") : localized("Kết quả cho “%@”", query),
            tracks: results
        )
        .searchable(text: $query, placement: .toolbar, prompt: localized("Tìm bài hát"))
    }
}
