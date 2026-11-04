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

    /// The live feed. One task drinks the post stream for the whole app, because the stream behind it
    /// has exactly one consumer.
    private var liveTask: Task<Void, Never>?

    /// Bumped by every walk that starts, so a cancelled walk can recognise that the handle it
    /// is about to clear is not its own.
    private var generation = 0

    /// Folded haystacks, so a keystroke re-folds only what the last page brought in.
    private var haystacks: [String: String] = [:]

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
    ///
    /// Arming the live feed is part of asking for the library: a screen that wants the songs wants the
    /// ones that arrive after it opened too.
    func run(_ session: TelegramSession, library: Library) {
        watch(session, library: library)
        if tracks.isEmpty { tracks = library.storedTracks }
        startWalk(session, library: library, replacing: false)
    }

    /// Starts watching for the posts the allow-listed channels make while the app is open, so a new
    /// song is in the library the moment Telegram delivers it rather than at the next pull-to-refresh.
    ///
    /// Idempotent: every screen that calls `run` calls this, and one reader is what the stream allows.
    /// A logout closes the client, which finishes the stream, which ends the loop and lets the next
    /// session's posts be watched by a fresh one.
    func watch(_ session: TelegramSession, library: Library) {
        guard liveTask == nil, let messages = session.newMessages() else { return }
        let files = session.covers()
        let feed = Task {
            for await message in messages {
                guard let track = TdTrack(message: message), track.isAudio else { continue }
                ingest(track, library: library, with: files)
            }
            liveTask = nil
        }
        liveTask = feed
    }

    /// One post that has just landed, put in the library and on the screen.
    ///
    /// The allow-list is checked here rather than by the feed because TDLib sends the posts of every
    /// chat the account is in, and this library only grows with the channels the user agreed to have
    /// read.
    private func ingest(_ track: TdTrack, library: Library, with files: TdFileDownloader?) {
        guard library.indexedChannels.contains(where: { $0.chatId == track.chatId }),
              !tracks.contains(where: { $0.uniqueId == track.uniqueId })
        else { return }
        library.ingest(track, with: files)
        // A walk owns the list while it runs — it publishes the store when it ends, and the store has
        // the new row by then, so handing the list over now would only jump the rows around under a
        // walk that is about to reorder them anyway.
        guard !isReading else { return }
        tracks = library.storedTracks
        if case let .finished(snapshot) = phase {
            phase = .finished(.init(trackCount: tracks.count, messageCount: snapshot.messageCount,
                                    pageCount: snapshot.pageCount))
        }
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
        // The store publishes the finished list, not the walk. They are the same songs, and the
        // stored copy knows two things the post never did: the length the app read off the file of a
        // document post — Telegram sends no duration there (`td_api.tl:594`) — and where the copy on
        // the phone is.
        library.refresh()
        tracks = library.storedTracks
        if let failure {
            phase = .failed(failure)
        } else {
            phase = .finished(.init(trackCount: collected.count, messageCount: messages,
                                    pageCount: pages))
        }
    }

    /// Newest first, the way a chat reads. TDLib's page order is its own business, so the list
    /// is ordered here rather than trusted.
    private static func newestFirst(_ tracks: some Sequence<any Playable>) -> [any Playable] {
        tracks.sorted { $0.date != $1.date ? $0.date > $1.date : $0.messageId > $1.messageId }
    }

    /// TDLib's own code is the useful half of a failure: `USERNAME_NOT_OCCUPIED` and
    /// `CHANNEL_METHOD_INVALID` are different fixes, and a translation table for them would be a
    /// guess. The allow-list screens report through here too.
    static func describe(_ error: any Error) -> String {
        if let failure = error as? TdClient.Failure { return failure.description }
        if let failure = error as? TdChannelReader.Failure, case .channelNotFound(let name) = failure {
            return "Không tìm thấy kênh @\(name)"
        }
        return "\(error)"
    }
}
