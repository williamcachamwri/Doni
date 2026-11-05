import Foundation

/// A sentence around a value, kept as a literal key so it stays translatable: interpolating inside
/// `Text("Phát tất cả \(title)")` makes the SwiftUI key depend on the argument's type (`%@` vs `%lld`),
/// which no translation table can name. `Scripts/build-strings.py` insists on a row for each key here.
/// A wrong placeholder costs a lookup and falls back to the Vietnamese source, never a crash.
func localized(_ key: String, _ arguments: CVarArg...) -> String {
    let text = NSLocalizedString(key, comment: "")
    guard !arguments.isEmpty else { return text }
    return String(format: text, arguments: arguments)
}
