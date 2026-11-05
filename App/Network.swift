import Foundation
import Network
import SwiftUI

/// Whether this phone has a path to the internet, for the one question it is worth asking: when a
/// song stops in the middle, is the network to blame or is Telegram?
///
/// `NWPathMonitor` rather than a probe request, because a probe is a thing sent off the phone and
/// the answer it gives is about one server rather than about the connection. Nothing here leaves
/// the device.
@MainActor
final class Network: ObservableObject {
    static let shared = Network()

    /// The last path the system reported. Assumed up at launch: the monitor answers within a
    /// heartbeat of starting, and a wrong "down" would stop a song that is playing fine.
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
