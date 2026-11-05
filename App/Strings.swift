import Foundation

/// A sentence the app says around a value.
///
/// `Text("Phát tất cả \(title)")` already is a localized key, but the key SwiftUI builds from it
/// depends on the Swift type of `title` — `%@` for a string, `%lld` for a count — so a translation
/// table cannot name it and the sentence is unanswerable in practice. Writing the key out as a plain
/// literal with the placeholder inside is what makes it translatable, and what lets
/// `Scripts/build-strings.py` insist on a row for it: a string the checker can see is a string the
/// checker can hold the table to.
///
/// A wrong placeholder costs a lookup and falls back to the Vietnamese source, never a crash.
func localized(_ key: String, _ arguments: CVarArg...) -> String {
    let text = NSLocalizedString(key, comment: "")
    guard !arguments.isEmpty else { return text }
    return String(format: text, arguments: arguments)
}
