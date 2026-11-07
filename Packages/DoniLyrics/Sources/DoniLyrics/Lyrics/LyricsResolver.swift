import Foundation
import Support

public enum LyricsResolver {
    /// Picks the words to show. `automatic` ranks every source the fetch was allowed to ask by
    /// quality; a named preference uses only that source, falling back to the pure-music flag alone —
    /// the reference's `LyricSourceMerger.resolve(_:preference:)` split, with LRCLIB added to the chain.
    public static func resolve(_ sources: LyricRawSources,
                               duration: TimeInterval,
                               preference: LyricSourcePreference = .automatic) -> LyricsPayload? {
        switch preference {
        case .automatic:
            return amll(sources, duration)
                ?? netEaseYRC(sources, duration, requiresTranslation: true)
                ?? qqVerbatim(sources, duration)
                ?? netEaseLRC(sources, duration)
                ?? lrclibSynced(sources, duration)
                ?? qqLineSynchronized(sources, duration)
                ?? lrclibPlain(sources, duration)
                ?? pureMusic(sources)
        case .amll:
            return amll(sources, duration) ?? pureMusic(sources)
        case .netease:
            return netEaseYRC(sources, duration, requiresTranslation: false)
                ?? netEaseLRC(sources, duration)
                ?? pureMusic(sources)
        case .qqMusic:
            return qqVerbatim(sources, duration)
                ?? qqLineSynchronized(sources, duration)
                ?? pureMusic(sources)
        case .lrclib:
            return lrclibSynced(sources, duration)
                ?? lrclibPlain(sources, duration)
                ?? pureMusic(sources)
        }
    }

    // MARK: One rung each

    private static func amll(_ sources: LyricRawSources, _ duration: TimeInterval) -> LyricsPayload? {
        guard let amll = sources.amllTTML.flatMap(filled),
              !LyricsRenderer.lines(.amll(amll), duration: duration).isEmpty else { return nil }
        return .amll(amll)
    }

    private static func netEaseYRC(_ sources: LyricRawSources, _ duration: TimeInterval,
                                   requiresTranslation: Bool) -> LyricsPayload? {
        guard let netEase = sources.netEase,
              filled(netEase.yrc) != nil,
              !requiresTranslation
                || filled(netEase.translatedYRC) != nil
                || filled(netEase.translatedLRC) != nil,
              !LyricsRenderer.lines(.netEase(netEase), duration: duration).isEmpty else { return nil }
        return .netEase(netEase)
    }

    private static func netEaseLRC(_ sources: LyricRawSources, _ duration: TimeInterval) -> LyricsPayload? {
        guard let netEase = sources.netEase, filled(netEase.lrc) != nil,
              !LyricsRenderer.lines(.netEase(netEase), duration: duration).isEmpty else { return nil }
        return .netEase(netEase)
    }

    private static func qqVerbatim(_ sources: LyricRawSources, _ duration: TimeInterval) -> LyricsPayload? {
        guard let qq = sources.qq, filled(qq.verbatim) != nil else { return nil }
        let payload = LyricsPayload.qq(qq, duetReferenceLRC: sources.netEase?.lrc)
        return LyricsRenderer.lines(payload, duration: duration).isEmpty ? nil : payload
    }

    private static func qqLineSynchronized(_ sources: LyricRawSources, _ duration: TimeInterval) -> LyricsPayload? {
        guard let qq = sources.qq, filled(qq.lineSynchronized) != nil else { return nil }
        let payload = LyricsPayload.qq(qq, duetReferenceLRC: sources.netEase?.lrc)
        return LyricsRenderer.lines(payload, duration: duration).isEmpty ? nil : payload
    }

    private static func lrclibSynced(_ sources: LyricRawSources, _ duration: TimeInterval) -> LyricsPayload? {
        guard case .synced = sources.lrclib,
              !LyricsRenderer.lines(.lrclib(sources.lrclib!), duration: duration).isEmpty else { return nil }
        return .lrclib(sources.lrclib!)
    }

    private static func lrclibPlain(_ sources: LyricRawSources, _ duration: TimeInterval) -> LyricsPayload? {
        guard case .plain = sources.lrclib,
              !LyricsRenderer.lines(.lrclib(sources.lrclib!), duration: duration).isEmpty else { return nil }
        return .lrclib(sources.lrclib!)
    }

    private static func pureMusic(_ sources: LyricRawSources) -> LyricsPayload? {
        sources.netEase?.isPureMusic == true ? .pureMusic : nil
    }

    private static func filled(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}