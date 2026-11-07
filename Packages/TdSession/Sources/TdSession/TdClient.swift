import Foundation

/// One TDLib client instance: a receive loop, request/response correlation and an ordered update stream.
///
/// Deliberately a class with a lock rather than an actor: the receive loop is a blocking C call that
/// must own its thread, and updates have to reach the consumer in arrival order — one `Task` per
/// message would let two race. Only the pending-request table is shared, under `lock`.
public final class TdClient: @unchecked Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// TDLib answered with an `error` object.
        case response(code: Int, message: String)
        case malformed(String)
        case closed

        public var description: String {
            switch self {
            case .response(let code, let message): "TDLib error \(code): \(message)"
            case .malformed(let detail): "TDLib sent something unreadable: \(detail)"
            case .closed: "The TDLib client is closed"
            }
        }
    }

    private let transport: any TdTransporting
    private let clientId: Int32
    private let lock = NSLock()
    private let receiveQueue = DispatchQueue(label: "local.doni.td.receive")
    private var pending: [String: CheckedContinuation<TdJSON, any Error>] = [:]
    private var extraSequence = 0
    private var isStarted = false
    private var isClosed = false
    /// TDLib's `authorizationStateClosed` has been received. The ClientManager delivers it only after it
    /// has destroyed the client and joined its scheduler threads, so this flag is what makes `exit()` safe.
    private var hasConfirmedClose = false
    private let stream: AsyncStream<TdJSON>
    private let yield: AsyncStream<TdJSON>.Continuation
    private let fileStream: AsyncStream<TdJSON>
    private let fileYield: AsyncStream<TdJSON>.Continuation
    private let messageStream: AsyncStream<TdJSON>
    private let messageYield: AsyncStream<TdJSON>.Continuation
    private let deleteStream: AsyncStream<TdJSON>
    private let deleteYield: AsyncStream<TdJSON>.Continuation

    /// Updates and unsolicited responses, in arrival order. `AsyncStream` has
    /// one consumer; the session layer fans out from here.
    public var updates: AsyncStream<TdJSON> { stream }

    /// The `file` inside every `updateFile` (`td_api.tl:11596`), on a stream of its own.
    ///
    /// A second consumer of `updates` would steal states from the login loop, so the receive loop
    /// copies file progress out here instead.
    public var files: AsyncStream<TdJSON> { fileStream }

    /// The `message` inside every `updateNewMessage` (`td_api.tl:11196`), on a stream of its own.
    ///
    /// Same reason as `files`; the copy is the message object rather than the update around it, which
    /// is the shape `TdTrack(message:)` already reads out of a history page.
    public var messages: AsyncStream<TdJSON> { messageStream }

    /// Every `updateDeleteMessages` (`td_api.tl:11523`), whole — `chat_id` and `message_ids` are the
    /// pair a library needs, and `is_permanent`/`from_cache` say nothing a listener can act on.
    ///
    /// This is what makes a song the user deleted in Telegram leave Cloud Music while the app is
    /// open, instead of at the next read.
    public var deletes: AsyncStream<TdJSON> { deleteStream }

    public init(transport: any TdTransporting, clientId: Int32) {
        self.transport = transport
        self.clientId = clientId
        let (stream, continuation) = AsyncStream<TdJSON>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.stream = stream
        self.yield = continuation
        let (fileStream, fileContinuation) = AsyncStream<TdJSON>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.fileStream = fileStream
        self.fileYield = fileContinuation
        let (messageStream, messageContinuation) = AsyncStream<TdJSON>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.messageStream = messageStream
        self.messageYield = messageContinuation
        let (deleteStream, deleteContinuation) = AsyncStream<TdJSON>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.deleteStream = deleteStream
        self.deleteYield = deleteContinuation
    }

    /// Starts the receive loop, once per instance: TDLib forbids two
    /// simultaneous receives.
    public func start(timeout: Double = 0.3) {
        lock.lock()
        guard !isStarted, !isClosed else { lock.unlock(); return }
        isStarted = true
        lock.unlock()

        receiveQueue.async { [self] in
            while !isClosedFlag() {
                let text = transport.receive(timeout: timeout)
                if let text, let json = TdJSON.parse(text) {
                    route(json)
                    noteClosed(json)
                }
            }
        }
    }

    /// Sends a request and waits for the response matched by `@extra`.
    ///
    /// TDLib requests cannot be cancelled once sent, so this ignores task cancellation: a caller that
    /// goes away leaves the request to complete, as it would even if cancellation were honoured.
    public func request(_ type: String, _ fields: [String: TdJSON] = [:]) async throws -> TdJSON {
        let extra = nextExtra()
        var payload = fields
        payload["@type"] = .string(type)
        payload["@extra"] = .string(extra)
        guard let text = TdJSON.object(payload).serialized else { throw Failure.malformed(type) }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if isClosed {
                lock.unlock()
                continuation.resume(throwing: Failure.closed)
                return
            }
            pending[extra] = continuation
            lock.unlock()
            transport.send(clientId: clientId, request: text)
        }
    }

    /// For the handful of requests documented as synchronous, e.g.
    /// `getTextEntities`. Bypasses the loop, so the transport has to serialise
    /// the shared return buffer against `receive`.
    public func execute(_ type: String, _ fields: [String: TdJSON] = [:]) -> TdJSON? {
        var payload = fields
        payload["@type"] = .string(type)
        guard let text = TdJSON.object(payload).serialized else { return nil }
        return transport.execute(request: text).flatMap { TdJSON.parse($0) }
    }

    /// Closes the instance. Every client has to be closed before the process
    /// exits; pending requests are terminated with an error here.
    public func close() {
        lock.lock()
        if isClosed { lock.unlock(); return }
        isClosed = true
        let waiting = pending
        pending.removeAll()
        lock.unlock()

        transport.send(clientId: clientId, request: #"{"@type":"close"}"#)
        for continuation in waiting.values {
            continuation.resume(throwing: Failure.closed)
        }
        yield.finish()
        fileYield.finish()
        messageYield.finish()
        // The fourth stream this class owns. Left open, its reader never returns, and every re-login
        // adds another one bound to a client that no longer exists.
        deleteYield.finish()
    }

    /// Closes the instance and does not return until TDLib has finished tearing it down.
    ///
    /// Two waits, not one. `sync` on the loop's own queue gets the reader out of `td_receive` (the loop
    /// returns on its next 0.3-second turn). But `close` only *starts* the teardown: TDLib flushes its
    /// database on its own threads, and the ClientManager releases the client — joining those threads —
    /// only inside `receive`, when `authorizationStateClosed` comes back. A process that calls `exit()`
    /// before that delivery runs TDLib's static destructors mid-close: `ExitGuard` flips, the scheduler
    /// thread is detached instead of joined, and its destructor CHECK-fails on actors still running —
    /// `abort()`, the ⌘Q crash dialog. So after the join this thread owns receive (TDLib forbids two
    /// simultaneous receivers) and drains it until the closed update arrives. The loop may have consumed
    /// that update in its final turn, hence the flag rather than a drain-only wait. The deadline is the
    /// escape hatch for a close that never completes; proceeding then is no worse than not waiting.
    public func closeAndJoin() {
        close()
        receiveQueue.sync {}
        let deadline = Date().addingTimeInterval(10)
        while !closeConfirmedFlag(), Date() < deadline {
            guard let text = transport.receive(timeout: 0.3) else { continue }
            if let json = TdJSON.parse(text) { noteClosed(json) }
        }
    }

    private func nextExtra() -> String {
        lock.lock()
        defer { lock.unlock() }
        extraSequence += 1
        return "x\(clientId)-\(extraSequence)"
    }

    private func isClosedFlag() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }

    private func closeConfirmedFlag() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasConfirmedClose
    }

    private func noteClosed(_ json: TdJSON) {
        guard json.type == "updateAuthorizationState",
              json["authorization_state"]?.type == "authorizationStateClosed" else { return }
        lock.lock()
        hasConfirmedClose = true
        lock.unlock()
    }

    private func route(_ json: TdJSON) {
        if json.type == "updateFile", let file = json["file"] { fileYield.yield(file) }
        if json.type == "updateNewMessage", let message = json["message"] {
            messageYield.yield(message)
        }
        if json.type == "updateDeleteMessages" { deleteYield.yield(json) }
        if let extra = json["@extra"]?.string {
            lock.lock()
            let continuation = pending.removeValue(forKey: extra)
            lock.unlock()
            if let continuation {
                if json.type == "error" {
                    continuation.resume(
                        throwing: Failure.response(
                            code: Int(json["code"]?.int ?? 0),
                            message: json["message"]?.string ?? ""
                        )
                    )
                } else {
                    continuation.resume(returning: json)
                }
                return
            }
        }
        yield.yield(json)
    }
}
