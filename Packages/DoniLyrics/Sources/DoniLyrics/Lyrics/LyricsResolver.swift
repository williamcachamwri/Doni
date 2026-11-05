import Foundation
import Support

public enum LyricsResolver {
    public static func resolve(_ sources: LyricRawSources,
                               duration: TimeInterval) -> LyricsPayload? {
        let amll = sources.amllTTML.flatMap(filled)
        if let amll, !LyricsRenderer.lines(.amll(amll), duration: duration).isEmpty {
            return .amll(amll)
        }
        if let netEase = sources.netEase,
           filled(netEase.yrc) != nil,
           filled(netEase.translatedYRC) != nil || filled(netEase.translatedLRC) != nil,
           !LyricsRenderer.lines(.netEase(netEase), duration: duration).isEmpty {
            return .netEase(netEase)
        }
        if let qq = sources.qq, filled(qq.verbatim) != nil {
            let payload = LyricsPayload.qq(qq, duetReferenceLRC: sources.netEase?.lrc)
            if !LyricsRenderer.lines(payload, duration: duration).isEmpty {
                return payload
            }
        }
        if let netEase = sources.netEase, filled(netEase.lrc) != nil,
           !LyricsRenderer.lines(.netEase(netEase), duration: duration).isEmpty {
            return .netEase(netEase)
        }
        if case .synced = sources.lrclib,
           !LyricsRenderer.lines(.lrclib(sources.lrclib!), duration: duration).isEmpty {
            return .lrclib(sources.lrclib!)
        }
        if let qq = sources.qq, filled(qq.lineSynchronized) != nil {
            let payload = LyricsPayload.qq(qq, duetReferenceLRC: sources.netEase?.lrc)
            if !LyricsRenderer.lines(payload, duration: duration).isEmpty {
                return payload
            }
        }
        if case .plain = sources.lrclib,
           !LyricsRenderer.lines(.lrclib(sources.lrclib!), duration: duration).isEmpty {
            return .lrclib(sources.lrclib!)
        }
        if sources.netEase?.isPureMusic == true { return .pureMusic }
        return nil
    }

    private static func filled(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
