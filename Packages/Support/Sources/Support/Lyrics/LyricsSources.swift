import Foundation

public enum LyricsSources {
    public static func fetch(metadata: LyricSongMetadata,
                             session: URLSession = .shared,
                             preference: LyricSourcePreference = .automatic) async -> LyricsFetchOutcome {
        let query = LyricQuery(artist: metadata.artist, title: metadata.title,
                               duration: metadata.durationSeconds)
        var amllTTML: String?
        var netEasePayload: NetEaseLyricPayload?
        var qqPayload: QQLyricPayload?
        var lrclibText: LyricText?
        var failed = false

        await withTaskGroup(of: ProviderResult.self) { group in
            if preference.usesLRCLIB {
                group.addTask {
                    guard let value = await LRClib.fetch(query, session: session) else {
                        return .lrclibFailed
                    }
                    return .lrclib(value)
                }
            }
            // NetEase is always asked: it is the backbone AMLL keys off, and it carries the
            // pure-music flag every preference falls back to.
            group.addTask {
                do {
                    let result = try await NetEaseLyricsClient(session: session)
                        .lyrics(for: metadata, includesAMLL: preference.usesAMLL)
                    return .netEase(result.payload, result.amllTTML)
                } catch let error as LyricSourceError {
                    if case .noLyrics = error { return .netEaseMissing }
                    return .netEaseFailed
                } catch {
                    return .netEaseFailed
                }
            }
            if preference.usesQQ {
                group.addTask {
                    do {
                        return .qq(try await QQMusicLyricsClient(session: session)
                            .lyrics(for: metadata))
                    } catch let error as LyricSourceError {
                        if case .noLyrics = error { return .qqMissing }
                        return .qqFailed
                    } catch {
                        return .qqFailed
                    }
                }
            }

            for await result in group {
                switch result {
                case .lrclib(let value): lrclibText = value
                case .lrclibFailed, .netEaseFailed, .qqFailed: failed = true
                case .netEase(let payload, let ttml):
                    netEasePayload = payload
                    amllTTML = ttml
                case .netEaseMissing, .qqMissing: break
                case .qq(let payload): qqPayload = payload
                }
            }
        }

        let sources = LyricRawSources(amllTTML: amllTTML, netEase: netEasePayload,
                                      qq: qqPayload, lrclib: lrclibText)
        let hasLRCLIB: Bool
        if let value = lrclibText {
            switch value {
            case .synced, .plain: hasLRCLIB = true
            case LyricText.none: hasLRCLIB = false
            }
        } else {
            hasLRCLIB = false
        }
        let hasAny = sources.amllTTML != nil || sources.netEase != nil
            || sources.qq != nil || hasLRCLIB
        if hasAny { return .sources(sources) }
        return failed ? .failed : .none
    }

    private enum ProviderResult {
        case lrclib(LyricText)
        case lrclibFailed
        case netEase(NetEaseLyricPayload, String?)
        case netEaseMissing
        case netEaseFailed
        case qq(QQLyricPayload)
        case qqMissing
        case qqFailed
    }
}
