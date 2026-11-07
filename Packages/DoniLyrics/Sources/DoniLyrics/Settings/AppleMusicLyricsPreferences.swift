import Foundation
import Observation

@MainActor
@Observable
public class AppleMusicLyricsPreferences {
    private enum Key {
        static let motionPreset =
            "melox.lyrics.appleMusic.motionPreset"
    }

    private enum Default {
        static let motionPreset: AppleMusicLyricsMotionPreset =
            .appleMusic26
    }

    public var motionPreset: AppleMusicLyricsMotionPreset {
        didSet {
            defaults.set(
                motionPreset.rawValue,
                forKey: Key.motionPreset
            )
        }
    }

    public var usesAppleMusic26Motion: Bool {
        motionPreset == .appleMusic26
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        motionPreset = AppleMusicLyricsMotionPreset(
            rawValue: defaults.string(forKey: Key.motionPreset) ?? ""
        ) ?? Default.motionPreset
    }

    public func reset() {
        motionPreset = Default.motionPreset
    }
}
