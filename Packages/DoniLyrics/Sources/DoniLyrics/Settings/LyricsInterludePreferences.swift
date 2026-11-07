import Foundation
import Observation

public enum LyricsInterludePresentationMode:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case hidden
    case preciseTiming
    case automatic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hidden:
            L10n.string("ui.common.off")
        case .preciseTiming:
            L10n.string("ui.settings.lyrics.interlude.precise")
        case .automatic:
            L10n.string("ui.settings.lyrics.interlude.automatic")
        }
    }

    public var description: String {
        switch self {
        case .hidden:
            L10n.string("ui.settings.lyrics.interlude.hidden.detail")
        case .preciseTiming:
            L10n.string("ui.settings.lyrics.interlude.precise.detail")
        case .automatic:
            L10n.string("ui.settings.lyrics.interlude.automatic.detail")
        }
    }

}

@MainActor
@Observable
public class LyricsInterludePreferences {
    public static let inferredGapDurationRange = 3.0...12.0
    public static let defaultMode: LyricsInterludePresentationMode = .automatic
    public static let defaultMinimumInferredGapDuration = 4.0

    private enum Key {
        static let mode = "melox.lyrics.interlude.mode"
        static let minimumInferredGapDuration =
            "melox.lyrics.interlude.minimumInferredGapDuration"
        static let legacyEnabled = "lyricsInterludeCountdownEnabled"
    }

    public var mode: LyricsInterludePresentationMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }

    public var minimumInferredGapDuration: TimeInterval {
        didSet {
            defaults.set(
                minimumInferredGapDuration,
                forKey: Key.minimumInferredGapDuration
            )
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let storedMode = defaults.string(forKey: Key.mode),
           let mode = LyricsInterludePresentationMode(
               rawValue: storedMode
           ) {
            self.mode = mode
        } else if let legacyEnabled = defaults.object(
            forKey: Key.legacyEnabled
        ) as? Bool {
            mode = legacyEnabled ? .automatic : .hidden
        } else {
            mode = Self.defaultMode
        }

        let storedMinimum = defaults.object(
            forKey: Key.minimumInferredGapDuration
        ) as? Double ?? Self.defaultMinimumInferredGapDuration
        minimumInferredGapDuration = min(
            max(storedMinimum, Self.inferredGapDurationRange.lowerBound),
            Self.inferredGapDurationRange.upperBound
        )
    }

    public func reset() {
        mode = Self.defaultMode
        minimumInferredGapDuration =
            Self.defaultMinimumInferredGapDuration
    }
}
