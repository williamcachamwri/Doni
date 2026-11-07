#if os(iOS)
import SwiftUI

/// Keeps runtime lyric runs in one attributed string. Repeated Text interpolation
/// nests localization work inside every character and stalls layout on long lines.
public struct LyricAttributedText {
    private var content: AttributedString

    public init(verbatim source: String) {
        content = AttributedString(source)
    }

    mutating func append(_ fragment: Self) {
        content.append(fragment.content)
    }

    public func customAttribute(_ timing: LyricTimingTextAttribute) -> Self {
        var result = self
        result.content[LyricTimingAttributeKey.self] = timing
        return result
    }

    public func customAttribute(_ placement: LyricRubyPlacementTextAttribute) -> Self {
        var result = self
        result.content[LyricPlacementAttributeKey.self] = placement
        return result
    }

    public var text: Text {
        #if os(macOS)
        if #unavailable(macOS 26) {
            // macOS 15 supports nonlocalized Text concatenation, but cannot
            // pass attributed-string keys to TextRenderer yet.
            return content.runs.reduce(Text(verbatim: "")) { result, run in
                var fragment = Text(verbatim: String(content[run.range].characters))
                if let timing = run[LyricTimingAttributeKey.self] {
                    fragment = fragment.customAttribute(timing)
                }
                if let placement = run[LyricPlacementAttributeKey.self] {
                    fragment = fragment.customAttribute(placement)
                }
                return result + fragment
            }
        }
        #endif
        return Text(content)
    }
}

nonisolated private enum LyricTimingAttributeKey: AttributedStringKey {
    typealias Value = LyricTimingTextAttribute
    public static let name = "MeloX.lyricTiming"
}

nonisolated private enum LyricPlacementAttributeKey: AttributedStringKey {
    typealias Value = LyricRubyPlacementTextAttribute
    public static let name = "MeloX.lyricPlacement"
}

nonisolated private struct LyricAttributeScope: AttributeScope {
    public let timing: LyricTimingAttributeKey
    public let placement: LyricPlacementAttributeKey
    public let swiftUI: AttributeScopes.SwiftUIAttributes
}

@available(iOS 26, macOS 26, *)
private struct LyricTextFormatting: AttributedTextFormattingDefinition {
    public var body: some AttributedTextFormattingDefinition<LyricAttributeScope> {}
}

extension View {
    @ViewBuilder
    public func lyricTextAttributes() -> some View {
        if #available(iOS 26, macOS 26, *) {
            attributedTextFormattingDefinition(LyricTextFormatting())
        } else {
            self
        }
    }
}
#endif
