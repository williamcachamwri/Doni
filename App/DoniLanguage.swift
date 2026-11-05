import Foundation

/// The six languages Doni speaks — Chinese, Vietnamese, Spanish, Russian, French, Arabic — and the one
/// this phone should show. The catalog is keyed by the Vietnamese source, so a string with no entry in
/// the chosen language says itself in Vietnamese rather than disappearing; that is what lets translations
/// be filled a screen at a time.
enum DoniLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi"
    case chinese = "zh-Hans"
    case spanish = "es"
    case russian = "ru"
    case french = "fr"
    case arabic = "ar"

    var id: String { rawValue }

    /// The name in its own script: this screen must be readable before a language is chosen, and the Latin
    /// gloss tells two unfamiliar words apart.
    var nativeName: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .chinese: return "简体中文"
        case .spanish: return "Español"
        case .russian: return "Русский"
        case .french: return "Français"
        case .arabic: return "العربية"
        }
    }

    /// Whether the screen reads right to left. Arabic is the only one of the six, said out loud because
    /// the panel's geometry is points from the left edge and does not follow system mirroring.
    var isRightToLeft: Bool { self == .arabic }

    // MARK: Reading and writing the choice

    /// The system's own key. Writing here rather than keeping a private preference is the trick: every
    /// string in the app — including those the copied lyrics screen asks for by key, from a package with
    /// no bundle of its own — resolves out of the app's catalog against this list.
    private static let defaultsKey = "AppleLanguages"

    /// The language the user picked in Settings, or `nil` when they never have.
    static var stored: DoniLanguage? {
        guard isChosen else { return nil }
        guard let first = UserDefaults.standard.stringArray(forKey: defaultsKey)?.first else {
            return nil
        }
        return match(first)
    }

    /// Whether a choice was ever made. Not readable off `AppleLanguages` — following the phone writes that
    /// list too, and a phone that later changes language has to change Doni with it.
    private static let chosenKey = "local.doni.language.chosen"

    static var isChosen: Bool {
        UserDefaults.standard.bool(forKey: chosenKey)
    }

    /// What the app is showing: the choice if there is one, the device's own language otherwise.
    static var current: DoniLanguage { stored ?? automatic() ?? .vietnamese }

    /// The device's language, region as tie-breaker. A phone set to Chinese in Taiwan still reads the
    /// Simplified catalog — the one Chinese catalog this app carries; the region decides between the six.
    private static func automatic() -> DoniLanguage? {
        let locale = Locale.current
        guard let code = locale.language.languageCode?.identifier else { return nil }
        if let exact = match(code) { return exact }
        // A region can put a speaker inside the six when the language tag does not: French in Canada,
        // Arabic in Morocco.
        guard let region = locale.region?.identifier else { return nil }
        switch region {
        case "VN": return .vietnamese
        case "CN", "SG", "TW", "HK", "MO": return .chinese
        case "ES", "MX", "AR", "CO", "CL", "PE": return .spanish
        case "RU", "BY", "KZ": return .russian
        case "FR", "BE", "CH": return .french
        default: return nil
        }
    }

    /// `zh-Hans` and `zh-Hant-CN` both belong to Chinese, so a tag is matched whole first, then by its
    /// leading language subtag.
    private static func match(_ tag: String) -> DoniLanguage? {
        if let exact = DoniLanguage(rawValue: tag) { return exact }
        let head = String(tag.prefix(2))
        return allCases.first { $0.rawValue.hasPrefix(head) }
    }

    /// Writing the choice. The system reads this list once, when the process starts, so the new language
    /// arrives on the next launch rather than halfway down a screen — which the offering screen says.
    static func apply(_ language: DoniLanguage) {
        write(language, chosen: true)
    }

    /// Following the phone, for a user who has never chosen: written every launch, so a device language
    /// change moves Doni one launch later — the best the system allows.
    static func followDevice() {
        guard let device = automatic() else { return }
        write(device, chosen: false)
    }

    /// The two writers differ only in whether the app is now pinned — `chosen` cannot be read back out of
    /// `AppleLanguages`, because following the phone writes that list too.
    private static func write(_ language: DoniLanguage, chosen: Bool) {
        UserDefaults.standard.set([language.rawValue], forKey: defaultsKey)
        UserDefaults.standard.set(chosen, forKey: chosenKey)
    }
}
