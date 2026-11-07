import Foundation

public enum LyricsTypography {
    public static let heavySerifFontName = "SourceHanSerifCN-Heavy"
    public static let latinSerifFontName = "TimesNewRomanPS-BoldMT"

    public static func normalizedDisplayText(_ source: String) -> String {
        let text = source
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "……" : text
    }

    public static func isPredominantlyLatin(_ text: String) -> Bool {
        var visibleCount = 0
        var latinCount = 0

        for scalar in text.unicodeScalars {
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  !CharacterSet.punctuationCharacters.contains(scalar) else {
                continue
            }
            visibleCount += 1
            if scalar.isASCII, CharacterSet.letters.contains(scalar) {
                latinCount += 1
            }
        }

        guard visibleCount > 0 else { return false }
        return Double(latinCount) / Double(visibleCount) >= 0.7
    }
}
