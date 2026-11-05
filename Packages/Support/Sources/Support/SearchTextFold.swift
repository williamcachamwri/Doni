import Foundation

/// Normalises text so a Vietnamese query typed without tone marks still hits the accented original
/// ("em ghi dieu anh dan do" matches "Em ghi điều anh dặn dò").
///
/// Neither obvious mechanism is enough, both verified on this machine: `folding(.diacriticInsensitive)`
/// leaves `đ`/`Đ` untouched, and SQLite's `unicode61 remove_diacritics 2` covers U+00C0-U+00FF and
/// U+0100-U+017F but not Latin Extended Additional (U+1EA0-U+1EF9), where most Vietnamese precomposed
/// vowels live — an FTS5 query for an accented title returns zero rows. The ICU `Latin-ASCII` transform
/// folds the whole set, so it drives the pipeline and folding only mops up what it leaves behind.
public enum SearchTextFold {
    public static func normalized(_ input: String) -> String {
        let lowered = input.lowercased()
        let ascii = lowered.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) ?? lowered
        let folded = ascii.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
