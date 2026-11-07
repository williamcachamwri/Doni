import Foundation

public enum AppleMusicLyricsMotionPreset: String, CaseIterable, Identifiable {
    case appleMusic26
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleMusic26:
            L10n.string("ui.settings.lyrics.motion_preset.apple_music_26")
        case .custom:
            L10n.string("ui.common.custom")
        }
    }

    public var description: String {
        switch self {
        case .appleMusic26:
            L10n.string("ui.settings.lyrics.motion_preset.apple_music_26.mobile_detail")
        case .custom:
            L10n.string("ui.settings.lyrics.motion_preset.custom.detail")
        }
    }
}
