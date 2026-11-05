import Foundation
import Network
import SwiftUI

/// Whether this phone has a path to the internet, for when a song stops mid-playback: is the network to
/// blame or Telegram? `NWPathMonitor` over a probe request — a probe answers about one server, not the
/// connection, and nothing here leaves the device.
@MainActor
final class Network: ObservableObject {
    static let shared = Network()

    /// The last path the system reported. Assumed up at launch: the monitor answers immediately, and a
    /// wrong "down" would stop a song that is playing fine.
    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard Network.shared.isOnline != online else { return }
                Network.shared.isOnline = online
                print("network \(online ? "up" : "down")")
            }
        }
        monitor.start(queue: DispatchQueue(label: "local.doni.network"))
    }
}
