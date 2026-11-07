import Foundation

public enum LyricsLiftMode: String, CaseIterable, Identifiable, Sendable {
    case word
    case character

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .word:
            L10n.string("ui.settings.lyrics.lift.word")
        case .character:
            L10n.string("ui.settings.lyrics.lift.character")
        }
    }
}
