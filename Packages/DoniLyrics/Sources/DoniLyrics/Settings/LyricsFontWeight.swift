import SwiftUI
import Support

#if os(macOS)
    import AppKit
#endif

public enum LyricsFontWeight: String, CaseIterable, Identifiable {
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .light: L10n.string("ui.settings.font_weight.light")
        case .regular: L10n.string("ui.settings.font_weight.regular")
        case .medium: L10n.string("ui.settings.font_weight.medium")
        case .semibold: L10n.string("ui.settings.font_weight.semibold")
        case .bold: L10n.string("ui.settings.font_weight.bold")
        case .heavy: L10n.string("ui.settings.font_weight.heavy")
        }
    }

    public var swiftUIWeight: Font.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }

    public var doniWeight: DoniFont.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

#if os(macOS)
    extension LyricsFontWeight {
        /// The desktop column draws ruby text through Core Text, which wants an `NSFont.Weight`. The
        /// phone has no AppKit, so this lives behind the same guard as its only caller.
        public var appKitWeight: NSFont.Weight {
            switch self {
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            }
        }
    }
#endif
