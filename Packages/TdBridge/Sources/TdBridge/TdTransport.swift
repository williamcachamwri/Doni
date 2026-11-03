import Foundation
import TdLibC

/// The whole of TDLib's JSON surface: four C functions and a set of rules
/// taken from `td/telegram/td_json_client.h`.
///
/// Two of those rules shape everything above this layer:
/// - `td_receive` must not run on two threads at once, and updates have to be
///   applied in the order they arrive, so exactly one consumer owns the loop.
/// - the buffer `td_receive` and `td_execute` return is freed by the *next*
///   call to either one, so a synchronous `td_execute` is not thread-safe
///   against a running receive loop and both are serialised here.
///
/// Request/response correlation is TDLib's `@extra` field, which the caller
/// sets and TDLib echoes back on the matching response; that belongs to the
/// session layer above, not here.
public enum TdTransport {
    private static let bufferLock = NSLock()

    /// Opaque id for a new client instance. Updates start flowing only after
    /// the first `send`.
    public static func createClientId() -> Int32 {
        td_create_client_id()
    }

    public static func send(clientId: Int32, request: String) {
        request.withCString { td_send(clientId, $0) }
    }

    /// Blocks up to `timeout` seconds. Nil means the timeout expired.
    ///
    /// Exactly one thread may call this: TDLib forbids two simultaneous
    /// receives, and Swift cannot express that constraint for a free function.
    public static func receive(timeout: Double) -> String? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard let raw = td_receive(timeout) else { return nil }
        return String(cString: raw)
    }

    /// For requests documented as "can be called synchronously". Shares the
    /// return buffer with `receive`, hence the same lock.
    public static func execute(request: String) -> String? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return request.withCString { raw in
            guard let result = td_execute(raw) else { return nil }
            return String(cString: result)
        }
    }

    /// One-line health check used by the M0 harness: no session, no api_id, no
    /// network. Returns a human-readable verdict rather than throwing, because
    /// its only job is to be displayed.
    public static func probe() -> String {
        guard let response = execute(
            request: #"{"@type":"getTextEntities","text":"@telegram"}"#
        ), let data = response.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["@type"] as? String
        else {
            return "TDLib: no response"
        }
        let count = (object["entities"] as? [Any])?.count ?? 0
        return type == "textEntities"
            ? "TDLib linked — \(count) entities"
            : "TDLib replied \(type)"
    }
}
