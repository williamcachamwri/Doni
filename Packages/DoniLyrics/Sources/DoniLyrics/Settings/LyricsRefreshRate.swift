import SwiftUI

public enum LyricsRefreshRate: Int, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60
    case fps90 = 90
    case fps120 = 120

    public static let defaultValue = LyricsRefreshRate.fps60
    public static let lowPowerValue = LyricsRefreshRate.fps30

    public var id: Int { rawValue }

    public var title: String {
        "\(rawValue) FPS"
    }

    public var minimumInterval: TimeInterval {
        1.0 / Double(rawValue)
    }
}

private struct EffectiveLyricsRefreshRateKey: EnvironmentKey {
    public static let defaultValue = LyricsRefreshRate.defaultValue
}

/// Whether the lyrics subtree should still be driven frame by frame. The desktop column reads it to
/// pause its own `TimelineView`s; it defaults to on, so nothing that does not set it changes.
private struct LyricsRenderingIsActiveKey: EnvironmentKey {
    public static let defaultValue = true
}

extension EnvironmentValues {
    public var effectiveLyricsRefreshRate: LyricsRefreshRate {
        get { self[EffectiveLyricsRefreshRateKey.self] }
        set { self[EffectiveLyricsRefreshRateKey.self] = newValue }
    }

    public var lyricsRenderingIsActive: Bool {
        get { self[LyricsRenderingIsActiveKey.self] }
        set { self[LyricsRenderingIsActiveKey.self] = newValue }
    }
}
