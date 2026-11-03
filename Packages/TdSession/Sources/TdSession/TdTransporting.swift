import Foundation

/// The four TDLib JSON entry points, as a seam.
///
/// `TdBridge` implements this over the C functions; keeping it a protocol is
/// what lets the session layer be tested on the host toolchain, where the
/// iOS-only xcframework cannot be linked.
public protocol TdTransporting: Sendable {
    func send(clientId: Int32, request: String)

    /// Blocks up to `timeout` seconds and returns nil on timeout. Called from
    /// exactly one thread by `TdClient`, as TDLib requires.
    func receive(timeout: Double) -> String?

    /// Only for requests the schema marks "Can be called synchronously".
    func execute(request: String) -> String?
}
