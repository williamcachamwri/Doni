#if os(iOS)
import Foundation

/// Solver inputs for a physical spring. Values are normalized on creation so
/// animation code never hands non-finite or non-physical inputs to SwiftUI.
public nonisolated struct LyricPhysicalSpringParameters: Equatable, Sendable {
    public let mass: Double
    public let stiffness: Double
    public let damping: Double

    public init(
        mass: Double,
        stiffness: Double,
        damping: Double
    ) {
        self.mass = Self.positiveFinite(mass, fallback: 1)
        self.stiffness = Self.positiveFinite(stiffness, fallback: 1)
        self.damping = Self.nonnegativeFinite(damping, fallback: 0)
    }

    public var dampingRatio: Double {
        damping / (2 * sqrt(mass * stiffness))
    }

    public var undampedPeriod: TimeInterval {
        2 * .pi * sqrt(mass / stiffness)
    }

    private static func positiveFinite(
        _ value: Double,
        fallback: Double
    ) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func nonnegativeFinite(
        _ value: Double,
        fallback: Double
    ) -> Double {
        value.isFinite && value >= 0 ? value : fallback
    }
}
#endif
