// doni:ios-renderer — the desktop column is DoniLyricsDesktop's own copy
#if os(iOS)
import SwiftUI

// The reference annotates this `@MainActor`. It only builds `Text` values, and the row
// builder that calls it is not on the main actor, so under this toolchain the annotation
// is a hard isolation error rather than the nothing it was where it was written.
public enum LyricRubyTextBuilder {
    public static func romanizationText(
        from units: [LyricRubyPlacementUnit]
    ) -> Text {
        units.reduce(into: LyricAttributedText(verbatim: "")) { result, unit in
            guard let romanization = unit.lyric.romanizationText else {
                return
            }
            let fragment: LyricAttributedText
            if hasTimedRomanization(unit.lyric) {
                fragment = timedText(
                    syllables:
                        unit.lyric.romanizationSyllables
                )
            } else {
                fragment = LyricAttributedText(verbatim: romanization)
            }
            let placedFragment = fragment.customAttribute(
                LyricRubyPlacementTextAttribute(
                    horizontalOffset: unit.romanizationOffset
                )
            )
            result.append(placedFragment)
        }.text
    }

    public static func hasTimedRomanization(
        _ unit: LyricRubyUnit
    ) -> Bool {
        guard unit.hasAuthoredRomanizationTiming,
              let source = unit.romanizationText else {
            return false
        }
        let syllables = unit.romanizationSyllables.filter {
            !$0.text.isEmpty
        }
        return !syllables.isEmpty
            && syllables.map(\.text).joined() == source
    }

    private static func timedText(
        syllables: [LyricSyllable]
    ) -> LyricAttributedText {
        syllables.filter { !$0.text.isEmpty }.reduce(into:
            LyricAttributedText(verbatim: "")
        ) {
            result,
            syllable in
            let isWhitespace = syllable.text.allSatisfy(\.isWhitespace)
            let fragment = LyricAttributedText(verbatim: syllable.text)
                .customAttribute(
                    LyricTimingTextAttribute(
                        startTime: syllable.startTime,
                        endTime: max(
                            syllable.endTime,
                            syllable.startTime
                        ),
                        syllableStartTime: syllable.startTime,
                        syllableEndTime: max(
                            syllable.endTime,
                            syllable.startTime
                        ),
                        characterIndex: 0,
                        characterCount: 1,
                        wordStartTime: syllable.startTime,
                        wordEndTime: max(
                            syllable.endTime,
                            syllable.startTime
                        ),
                        wordCharacterIndex: 0,
                        wordCharacterCount: 1,
                        usesWordTimingForLongTone: false,
                        isWhitespace: isWhitespace
                    )
                )
            result.append(fragment)
        }
    }
}
#endif
