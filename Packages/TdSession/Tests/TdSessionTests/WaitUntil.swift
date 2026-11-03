import Foundation
import TdSession

/// Polls instead of sleeping a fixed amount, so the suite stays fast when the
/// receive loop is already ahead and still passes when it is not.
func polled(
    _ attempts: Int = 250,
    _ condition: @escaping @Sendable () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return false
}

func waitFor(
    attempts: Int = 250,
    _ condition: @escaping @Sendable () -> Bool
) async throws {
    if await polled(attempts, condition) { return }
    throw TdClient.Failure.malformed("condition never became true")
}
