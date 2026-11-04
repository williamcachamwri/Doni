import Foundation
import SwiftUI
import Support
import TdSession

/// Walks every channel on the allow-list, 100 messages at a time, and collects everything playable
/// in it.
///
/// Index-first: the app reads the whole channel before it decides what the library is, because a
/// music library that only knows the first screenful of posts is not a library. The loop keeps the
/// oldest message id it has seen and asks for messages older than that, which is the only direction
/// `getChatHistory` walks; a page with nothing older ends the channel. Each page is written to
/// `Library` as it lands, and the stored rows go on screen before the walk starts, so the list is
/// full the moment it is opened and the walk only has to improve it.
///
/// A channel is read by the chat id its row carries, which is resolved once by the screen that adds
/// it — see `TdChannelReader.probe`. The walk never looks a handle up: an allow-list the user filled
/// is a list of chats, not of usernames to keep re-resolving.
@MainActor
final class LibraryIndexer: ObservableObject {
    struct Snapshot: Equatable {
        var trackCount: Int
        var messageCount: Int
        var pageCount: Int
    }

    enum Phase: Equatable {
        case idle
        case reading(Snapshot)
        case finished(Snapshot)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var tracks: [any Playable] = []

    private var task: Task<Void, Never>?

    /// Bumped by every walk that starts, so a cancelled walk can recognise that the handle it
    /// is about to clear is not its own.
    private var generation = 0

    /// Folded haystacks, so a keystroke re-folds only what the last page brought in.
    private var haystacks: [String: String] = [:]

    /// The channel Doni was built around, and the one key that says its free offer was already made.
    static let defaultUsername = "VNMusicRemix"
    private static let seededDefaultKey = "library.seededDefaultChannel"

    var isReading: Bool {
        switch phase {
        case .reading:
            return true
        case .idle, .finished, .failed:
            return false
        }
    }

    /// The bar's second line, in the chat list's `secondaryTextColor`.
    var statusLine: String {
        switch phase {
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
        await seedDefaultChannel(reader, library: library)
        let targets = library.indexedChannels
        guard !targets.isEmpty else {
            phase = .finished(.init(trackCount: tracks.count, messageCount: 0, pageCount: 0))
            return
        }

        // Keyed by `unique_id`, which is the only id that means the same song in two sources: a walk
        // that re-reads a row overwrites the stored copy of it rather than doubling the list, and a
        // channel it never reaches keeps the rows already on screen.
        var collected: [String: any Playable] = Dictionary(
            uniqueKeysWithValues: tracks.map { ($0.uniqueId, $0) }
        )
        var messages = 0
        var pages = 0
        var failure: String?
        haystacks = [:]
        // A refresh over a library that is already on screen waits for the walk to end before it
        // publishes, so the list never re-sorts itself a thousand times under the finger — and never
        // shrinks to one page and grows back, because what it grows from is the screen's own rows.
        let publishAsItGoes = tracks.isEmpty

        for target in targets {
            guard !Task.isCancelled else { return }
            var cursor: Int64 = 0
            while !Task.isCancelled {
                let page: TdHistoryPage
                do {
                    page = try await reader.page(chatId: target.chatId, cursor: cursor)
                } catch {
                    // One channel that will not answer is not a reason to stop the others, but the
                    // first complaint is the one the screen gets to show.
                    failure = failure ?? Self.describe(error)
                    break
                }
                pages += 1
                messages += page.messages.count
                for track in page.tracks { collected[track.uniqueId] = track }
                library.remember(page: page.tracks, chatId: target.chatId)
                if publishAsItGoes { tracks = Self.newestFirst(collected.values) }
                phase = .reading(.init(trackCount: collected.count, messageCount: messages,
                                       pageCount: pages))

                guard !page.isLast, let oldest = page.oldestMessageId, oldest != cursor else { break }
                cursor = oldest
            }
        }

        guard !Task.isCancelled else { return }
        tracks = Self.newestFirst(collected.values)
        library.refresh()
        if let failure {
            phase = .failed(failure)
        } else {
            phase = .finished(.init(trackCount: collected.count, messageCount: messages,
                                    pageCount: pages))
        }
    }

    /// The first walk of an install gets the channel Doni was built around, because a library with
    /// no channels and no songs is a screen that does nothing. Offered once: a list the user emptied
    /// by hand is not a list to refill.
    private func seedDefaultChannel(_ reader: TdChannelReader, library: Library) async {
        guard library.channels.isEmpty,
              !UserDefaults.standard.bool(forKey: Self.seededDefaultKey)
        else { return }
        UserDefaults.standard.set(true, forKey: Self.seededDefaultKey)
        if let channel = try? await reader.channel(username: Self.defaultUsername) {
            library.add(channel)
        }
    }

    /// Newest first, the way a chat reads. TDLib's page order is its own business, so the list
    /// is ordered here rather than trusted.
    private static func newestFirst(_ tracks: some Sequence<any Playable>) -> [any Playable] {
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
