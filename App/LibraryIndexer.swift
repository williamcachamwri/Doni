import Foundation
import SwiftUI
import Support
import TdSession

/// Walks one channel's history, 100 messages at a time, and collects everything
/// playable in it.
///
/// Index-first: the app reads the whole channel before it shows a list, because
/// a music library that only knows the first screenful of posts is not a library.
/// The loop keeps the oldest message id it has seen and asks for messages older
/// than that, which is the only direction `getChatHistory` walks; a page shorter
/// than the limit ends the channel.
@MainActor
final class LibraryIndexer: ObservableObject {
    struct Snapshot: Equatable {
        var trackCount: Int
        var messageCount: Int
        var pageCount: Int
    }

    enum Phase: Equatable {
        case idle
        case resolving
        case reading(Snapshot)
        case finished(Snapshot)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var tracks: [TdTrack] = []
    @Published private(set) var channel: TdChannel?

    /// The row the list is holding. M3 makes this what the player is showing; until then it is
    /// the chat list's own `itemSelectedBackgroundColor` on one row.
    @Published private(set) var selectedId: String?

    private var task: Task<Void, Never>?

    /// Folded haystacks, so a keystroke re-folds only what the last page brought in.
    private var haystacks: [String: String] = [:]

    #if DEBUG
    /// Raw pages, kept only to compare the parser against a real channel.
    private var dump: [TdJSON] = []
    #endif

    /// The channel Doni was built around.
    static let username = "VNMusicRemix"

    /// Pages kept in the raw dump; see `writeDump`.
    private static let dumpPageCap = 3

    var isReading: Bool {
        switch phase {
        case .resolving, .reading:
            return true
        case .idle, .finished, .failed:
            return false
        }
    }

    /// The bar's second line, in the chat list's `secondaryTextColor`.
    var statusLine: String {
        switch phase {
        case .resolving:
            return "Đang mở @" + Self.username
        case let .reading(snapshot), let .finished(snapshot):
            return "\(snapshot.trackCount.formatted()) bài · đã đọc \(snapshot.messageCount.formatted()) tin"
        case .idle, .failed:
            return ""
        }
    }

    var failureLine: String? {
        guard case let .failed(text) = phase else { return nil }
        return text
    }

    /// Vietnamese search without tone marks: both sides go through
    /// `SearchTextFold.normalized`, so "tinh yeu" finds "Tình yêu".
    func matches(of rawQuery: String) -> [TdTrack] {
        let query = SearchTextFold.normalized(rawQuery)
        guard !query.isEmpty else { return tracks }
        for track in tracks where haystacks[track.uniqueId] == nil {
            haystacks[track.uniqueId] = SearchTextFold.normalized(
                "\(track.displayTitle) \(track.displayPerformer) \(track.fileName)"
            )
        }
        return tracks.filter { haystacks[$0.uniqueId]?.contains(query) ?? false }
    }

    func select(_ track: TdTrack) {
        selectedId = track.uniqueId
    }

    func run(_ session: TelegramSession) {
        guard task == nil else { return }
        guard let reader = session.reader() else { return }
        task = Task { await self.index(reader) }
    }

    func stop() {
        task?.cancel()
        task = nil
        // The loop breaks on cancellation without announcing a phase, so the walk is closed
        // here: what has been read is what there is.
        if case let .reading(snapshot) = phase { phase = .finished(snapshot) }
    }

    private func index(_ reader: TdChannelReader) async {
        phase = .resolving
        let channel: TdChannel
        do {
            channel = try await reader.channel(username: Self.username)
        } catch {
            phase = .failed(Self.describe(error))
            return
        }
        self.channel = channel

        var seen: Set<String> = []
        var collected: [TdTrack] = []
        var messages = 0
        var pages = 0
        var cursor: Int64 = 0

        while !Task.isCancelled {
            let page: TdHistoryPage
            do {
                page = try await reader.page(chatId: channel.chatId, cursor: cursor)
            } catch {
                phase = .failed(Self.describe(error))
                return
            }
            pages += 1
            messages += page.messages.count
            #if DEBUG
            if pages <= Self.dumpPageCap { dump.append(contentsOf: page.messages) }
            #endif

            for track in page.tracks where !seen.contains(track.uniqueId) {
                seen.insert(track.uniqueId)
                collected.append(track)
            }
            // Newest first, the way a chat reads. TDLib's page order is its own
            // business, so the list is ordered here rather than trusted.
            self.tracks = collected.sorted {
                $0.date != $1.date ? $0.date > $1.date : $0.messageId > $1.messageId
            }
            phase = .reading(.init(trackCount: collected.count, messageCount: messages, pageCount: pages))

            guard !page.isLast, let oldest = page.oldestMessageId, oldest != cursor else { break }
            cursor = oldest
        }

        writeDump()
        guard !Task.isCancelled else { return }
        phase = .finished(.init(trackCount: collected.count, messageCount: messages, pageCount: pages))
    }

    /// Task #10 of the plan: a real page of TDLib JSON, kept next to the database
    /// so the parser can be checked against what a channel actually posts. Debug
    /// builds only, never sent anywhere, and the first thing to delete once the
    /// parser is settled — it holds message content.
    private func writeDump() {
        #if DEBUG
        guard !dump.isEmpty, let text = TdJSON.array(dump).serialized else { return }
        let url = Self.dumpURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        #endif
    }

    private static var dumpURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Doni/debug/raw-index-dump.json")
    }

    static var dumpPath: String { dumpURL.path }

    private static func describe(_ error: any Error) -> String {
        if let failure = error as? TdClient.Failure { return failure.description }
        if let failure = error as? TdChannelReader.Failure, case .channelNotFound(let name) = failure {
            return "Không tìm thấy kênh @\(name)"
        }
        return "\(error)"
    }
}
