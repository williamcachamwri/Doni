import Foundation

/// The release notes bundled with this build: `Scripts/release-notes.py` writes them out of
/// `RELEASE_NOTES.md` at `make notes`. The JSON is committed, not generated during a build — XcodeGen
/// decides the bundle's resources when it makes the project, so a file a build phase creates first is
/// not in the package that build produces.
struct AppReleaseNotes: Equatable, Sendable {
    let version: String
    let entries: [String]

    static let empty = AppReleaseNotes(version: "", entries: [])

    /// Notes for the phone's language, English for anything else; Vietnamese is the development language
    /// the table's strings are keyed by.
    static func load() -> AppReleaseNotes {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.schemaVersion == schemaVersion else { return .empty }
        let language = Locale.preferredLanguages.first ?? "vi"
        let key = language.hasPrefix("vi") ? "vi" : "en"
        let entries = file.localizedEntries[key] ?? file.localizedEntries["en"] ?? []
        return AppReleaseNotes(version: file.version, entries: entries)
    }

    private static let schemaVersion = 1

    private struct File: Decodable, Sendable {
        let schemaVersion: Int
        let version: String
        let localizedEntries: [String: [String]]
    }
}

/// Whether this version's notes have already been shown. A sheet that returns on every launch gets
/// dismissed unread, so the last version shown is written down; notes with no entries never present.
enum AppReleaseNotesStore {
    private static let key = "releaseNotes.lastPresentedVersion"

    static func shouldPresent(_ notes: AppReleaseNotes) -> Bool {
        guard !notes.entries.isEmpty, !notes.version.isEmpty else { return false }
        guard let seen = UserDefaults.standard.string(forKey: key) else { return true }
        return AppVersion.compare(notes.version, to: seen) == .orderedDescending
    }

    static func markPresented(_ notes: AppReleaseNotes) {
        UserDefaults.standard.set(notes.version, forKey: key)
    }
}
