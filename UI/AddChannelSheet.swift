import SwiftUI
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
/// user already knows what it holds, and `getChats` answers for forty of them at once where a
/// probe costs one round trip each.
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
                    Text("Doni chỉ đọc kênh công khai, và chỉ những bài audio trong đó.")
                }

                Section {
                    if isListingJoined {
                        HStack(spacing: Self.rowGap) {
                            ProgressView()
                            Text("Đang mở danh sách kênh…")
                                .foregroundStyle(.secondary)
                        }
                    } else if joined.isEmpty {
                        Text("Bạn chưa tham gia kênh nào.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(joined, id: \.chatId) { channel in
                            joinedRow(channel)
                        }
                    }
                } header: {
                    Text("Kênh bạn đang tham gia")
                }
            }
            .formStyle(.grouped)
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

    // MARK: Rows

    /// The probe's answer and the only button on the screen: what is in the channel, and whether to
    /// read it.
    private func probeRow(_ probe: TdChannelProbe) -> some View {
        HStack(spacing: Self.rowGap) {
            channelTitle(probe.channel,
                         subtitle: probe.trackCount == 0
                             ? "Không có bài audio nào trong \(probe.messageCount) tin gần nhất"
                             : "≈\(probe.trackCount.formatted()) bài trong "
                                 + "\(probe.messageCount.formatted()) tin gần nhất")
            Spacer(minLength: 8)
            addButton(for: probe.channel)
        }
    }

    private func joinedRow(_ channel: TdChannel) -> some View {
        HStack(spacing: Self.rowGap) {
            channelTitle(channel, subtitle: nil)
            Spacer(minLength: 8)
            addButton(for: channel)
        }
    }

    private func channelTitle(_ channel: TdChannel, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: Self.textGap) {
            Text(channel.title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
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
                .accessibilityLabel("Thêm \(channel.title)")
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
        joined = (try? await reader.channels()) ?? []
    }
}
