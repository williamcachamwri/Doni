import Foundation

/// The six languages Doni speaks, and the one this phone should be showing.
///
/// Six, and only six: Chinese, Vietnamese, Spanish, Russian, French, Arabic. The catalog is keyed by
/// the Vietnamese source, so a string with no entry in the chosen language says itself in Vietnamese
/// rather than disappearing — which is what lets the translations be filled in a screen at a time.
enum DoniLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi"
    case chinese = "zh-Hans"
    case spanish = "es"
    case russian = "ru"
    case french = "fr"
    case arabic = "ar"

    var id: String { rawValue }

    /// The name in its own script. A list of languages is the one screen that must be readable before
    /// the language has been chosen, so "Русский" has to be recognisable to someone reading it as
    /// their second language too — and the Latin gloss is what tells two unfamiliar words apart.
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

    /// Whether the screen reads right to left in this language. Arabic is the only one of the six, and
    /// it is said out loud because the panel's own geometry is written in points from the left edge
    /// and does not follow the system's mirroring.
    var isRightToLeft: Bool { self == .arabic }

    // MARK: Reading and writing the choice

    /// The system's own key. Writing here rather than keeping a private preference is the whole
    /// trick: every string in the app — including the ones the copied lyrics screen asks for by key,
    /// which belong to a package that has no bundle of its own — is resolved out of the app's
    /// catalog against this list.
    private static let defaultsKey = "AppleLanguages"

    /// The language the user picked in Settings, or `nil` when they never have.
    static var stored: DoniLanguage? {
        guard isChosen else { return nil }
        guard let first = UserDefaults.standard.stringArray(forKey: defaultsKey)?.first else {
            return nil
        }
        return match(first)
    }

    /// Whether a choice was ever made. It cannot be read off `AppleLanguages` itself, because
    /// following the phone writes that list too — and a phone that later changes language has to
    /// change Doni with it.
    private static let chosenKey = "local.doni.language.chosen"

    static var isChosen: Bool {
        UserDefaults.standard.bool(forKey: chosenKey)
    }

    /// What the app is showing: the choice if there is one, the device's own language otherwise.
    static var current: DoniLanguage { stored ?? automatic() ?? .vietnamese }

    /// The device's language, with its region as the tie-breaker. A phone set to Chinese in Taiwan
    /// still reads Doni's Simplified catalog, because that is the one Chinese catalog this app
    /// carries — the region is what decides between the six, not between two spellings of one.
    private static func automatic() -> DoniLanguage? {
        let locale = Locale.current
        guard let code = locale.language.languageCode?.identifier else { return nil }
        if let exact = match(code) { return exact }
        // A region can put a speaker inside the six when the language tag does not: French in
        // Canada, Arabic in Morocco, Portuguese in Angola are all one lookup away.
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

    /// `zh-Hans` and `zh-Hant-CN` both belong to Chinese, so a tag is matched whole first and by its
    /// leading language subtag after.
    private static func match(_ tag: String) -> DoniLanguage? {
        if let exact = DoniLanguage(rawValue: tag) { return exact }
        let head = String(tag.prefix(2))
        return allCases.first { $0.rawValue.hasPrefix(head) }
    }

    /// Writing the choice. The system reads this list once, when the process starts, so the new
    /// language arrives on the next launch rather than halfway down a screen — which is why the
    /// screen that offers it says so.
    static func apply(_ language: DoniLanguage) {
        write(language, chosen: true)
    }

    /// Following the phone, for a user who has never chosen. Written on every launch, so a phone that
    /// changes language changes Doni with it — one launch later, which is the best the system allows.
    static func followDevice() {
        guard let device = automatic() else { return }
        write(device, chosen: false)
    }

    /// The two writers differ only in whether the app is now pinned. `chosen` is what tells them
    /// apart, because it cannot be read back out of `AppleLanguages` — following the phone writes
    /// that list too.
    private static func write(_ language: DoniLanguage, chosen: Bool) {
        UserDefaults.standard.set([language.rawValue], forKey: defaultsKey)
        UserDefaults.standard.set(chosen, forKey: chosenKey)
    }
}
