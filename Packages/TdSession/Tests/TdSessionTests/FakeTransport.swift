import Foundation
import TdSession

/// Scripts TDLib replies and records requests, so the session layer can be
/// tested without a network, a session or an iOS-only binary.
final class FakeTransport: TdTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var scripted: [String]
    private var sent: [String] = []
    private var executed: [String] = []
    private var consumed = 0
    var syncReply: String?

    /// How many scripted replies the receive loop has taken, so a test can tell a
    /// delivered message from one still sitting in the queue.
    var consumedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return consumed
    }

    init(replies: [String] = []) {
        scripted = replies
    }

    func queue(_ json: String) {
        lock.lock()
        scripted.append(json)
        lock.unlock()
    }

    func send(clientId: Int32, request: String) {
        lock.lock()
        sent.append(request)
        lock.unlock()
    }

    func receive(timeout: Double) -> String? {
        lock.lock()
        if !scripted.isEmpty {
            let next = scripted.removeFirst()
            consumed += 1
            lock.unlock()
            return next
        }
        lock.unlock()
        usleep(200)
        return nil
    }

    func execute(request: String) -> String? {
        lock.lock()
        executed.append(request)
        let reply = syncReply
        lock.unlock()
        return reply
    }

    var sentRequests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    var executedRequests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return executed
    }

    var decodedRequests: [TdJSON] {
        sentRequests.compactMap { TdJSON.parse($0) }
    }
}
