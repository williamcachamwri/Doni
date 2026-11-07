import Foundation

public enum LyricsTranslationDisplayMode: String, CaseIterable, Identifiable {
    case focusedLine
    case allLines

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .focusedLine:
            L10n.string("ui.settings.lyrics.auxiliary.focused_line")
        case .allLines:
            L10n.string("ui.settings.lyrics.auxiliary.all_lines")
        }
    }
}
