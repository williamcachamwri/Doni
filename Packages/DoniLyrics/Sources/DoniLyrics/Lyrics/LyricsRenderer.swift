import Foundation
import Support

public enum LyricsRenderer {
    public static func lines(_ payload: LyricsPayload, duration: TimeInterval) -> [LyricLine] {
        switch payload {
        case .amll(let ttml):
            return TTMLLyricParser.parse(ttml)
        case .netEase(let payload):
            return LyricParser.parse(
                yrc: payload.yrc ?? "",
                lrc: payload.lrc ?? "",
                translatedYRC: payload.translatedYRC ?? "",
                translatedLRC: payload.translatedLRC ?? "",
                romanizedYRC: payload.romanizedYRC ?? "",
                romanizedLRC: payload.romanizedLRC ?? ""
            )
        case .qq(let payload, let duetLRC):
            if let qrc = filled(payload.verbatim) {
                let lines = LyricParser.parse(
                    yrc: QRCLyricNormalizer.normalize(qrc),
                    lrc: payload.lineSynchronized ?? "",
                    translatedLRC: payload.translation ?? "",
                    romanizedYRC: payload.romanization.map(QRCLyricNormalizer.normalize) ?? "",
                    romanizedLRC: payload.romanization ?? "",
                    duetLRC: duetLRC
                )
                if !lines.isEmpty { return lines }
            }
            if let lrc = filled(payload.lineSynchronized) {
                return LyricParser.parse(
                    yrc: "",
                    lrc: lrc,
                    translatedLRC: payload.translation ?? "",
                    romanizedLRC: payload.romanization ?? "",
                    duetLRC: duetLRC
                )
            }
            return []
        case .lrclib(.synced(let text)):
            return LyricParser.parseLRC(text)
        case .lrclib(.plain(let text)):
            return spread(text, over: duration)
        case .lrclib(.none), .pureMusic:
            return []
        }
    }

    private static func spread(_ text: String, over duration: TimeInterval) -> [LyricLine] {
        let rows = text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !rows.isEmpty, duration > 0 else { return [] }
        let slice = duration / Double(rows.count)
        return rows.enumerated().map { index, row in
            LyricLine(
                time: Double(index) * slice,
                duration: slice,
                timingKind: .lineSynchronized,
                text: row
            )
        }
    }

    private static func filled(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
