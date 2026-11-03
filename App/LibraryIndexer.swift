import Foundation
import SwiftUI
import Support
import TdSession

/// Walks one channel's history, 100 messages at a time, and collects everything
/// playable in it.
///
/// Index-first: the app reads the whole channel before it decides what the library is, because a
/// music library that only knows the first screenful of posts is not a library. The loop keeps the
/// oldest message id it has seen and asks for messages older than that, which is the only direction
/// `getChatHistory` walks; a page shorter than the limit ends the channel. Each page is written to
/// `Library` as it lands, and the stored rows go on screen before the walk starts, so the list is
/// full the moment it is opened and the walk only has to improve it.
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
    @Published private(set) var tracks: [any Playable] = []
    @Published private(set) var channel: TdChannel?

    private var task: Task<Void, Never>?

    /// Bumped by every walk that starts, so a cancelled walk can recognise that the handle it
    /// is about to clear is not its own.
    private var generation = 0

    /// Folded haystacks, so a keystroke re-folds only what the last page brought in.
    private var haystacks: [String: String] = [:]

    /// The channel Doni was built around.
    static let username = "VNMusicRemix"

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
    func matches(of rawQuery: String) -> [any Playable] {
        let query = SearchTextFold.normalized(rawQuery)
        guard !query.isEmpty else { return tracks }
        for track in tracks where haystacks[track.uniqueId] == nil {
            haystacks[track.uniqueId] = SearchTextFold.normalized(
                "\(track.displayTitle) \(track.displayPerformer) \(track.fileName)"
            )
        }
        return tracks.filter { haystacks[$0.uniqueId]?.contains(query) ?? false }
    }

    /// Puts the stored library on screen first, then starts the walk if nothing is walking.
    /// `.task` on first appearance uses this.
    func run(_ session: TelegramSession, library: Library) {
        if tracks.isEmpty { tracks = library.storedTracks }
        startWalk(session, library: library, replacing: false)
    }

    /// Pull-to-refresh: the walk starts again from the newest message and the spinner is held
    /// until it ends. The rows already on screen stay — see `index`.
    func reload(_ session: TelegramSession, library: Library) async {
        guard let walk = startWalk(session, library: library, replacing: true) else { return }
        await walk.value
    }

    /// The handle is set before anything can suspend, so a second call while a walk is running
    /// either does nothing (a tap) or replaces it (a refresh) rather than racing it.
    @discardableResult
    private func startWalk(_ session: TelegramSession, library: Library,
                           replacing: Bool) -> Task<Void, Never>? {
        if replacing {
            stop()
        } else if task != nil {
            return nil
        }
        guard let reader = session.reader() else { return nil }
        generation += 1
        let mine = generation
        let walk = Task { await self.index(reader, library: library) }
        task = walk
        // Letting the handle go when the walk ends is what allows a second walk at all; the
        // generation check keeps a replaced walk from clearing the one that replaced it.
        Task {
            await walk.value
            if self.generation == mine { self.task = nil }
        }
        return walk
    }

    func stop() {
        task?.cancel()
        task = nil
        // The loop breaks on cancellation without announcing a phase, so the walk is closed
        // here: what has been read is what there is.
        if case let .reading(snapshot) = phase { phase = .finished(snapshot) }
    }

    private func index(_ reader: TdChannelReader, library: Library) async {
        phase = .resolving
        let channel: TdChannel
        do {
            channel = try await reader.channel(username: Self.username)
        } catch {
            phase = .failed(Self.describe(error))
            return
        }
        self.channel = channel
        library.remember(channel)

        var seen: Set<String> = []
        var collected: [TdTrack] = []
        var messages = 0
        var pages = 0
        var cursor: Int64 = 0
        haystacks = [:]
        // A refresh over a library that is already on screen waits for the walk to end before
        // it swaps, so the list never shrinks to one page and grows back under the finger.
        let publishAsItGoes = tracks.isEmpty

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

            for track in page.tracks where !seen.contains(track.uniqueId) {
                seen.insert(track.uniqueId)
                collected.append(track)
            }
            library.remember(page: page.tracks, chatId: channel.chatId)
            if publishAsItGoes { tracks = Self.newestFirst(collected) }
            phase = .reading(.init(trackCount: collected.count, messageCount: messages, pageCount: pages))

            guard !page.isLast, let oldest = page.oldestMessageId, oldest != cursor else { break }
            cursor = oldest
        }

        guard !Task.isCancelled else { return }
        if !publishAsItGoes { tracks = Self.newestFirst(collected) }
        library.refresh()
        phase = .finished(.init(trackCount: collected.count, messageCount: messages, pageCount: pages))
    }

    /// Newest first, the way a chat reads. TDLib's page order is its own business, so the list
    /// is ordered here rather than trusted.
    private static func newestFirst(_ tracks: [TdTrack]) -> [TdTrack] {
        tracks.sorted { $0.date != $1.date ? $0.date > $1.date : $0.messageId > $1.messageId }
    }

    private static func describe(_ error: any Error) -> String {
        if let failure = error as? TdClient.Failure { return failure.description }
        if let failure = error as? TdChannelReader.Failure, case .channelNotFound(let name) = failure {
            return "Không tìm thấy kênh @\(name)"
        }
        return "\(error)"
    }
}
