import Foundation

public enum LyricSource: String, Hashable, Sendable, Codable {
    case amll
    case netease
    case qqMusic
    case lrclib
}

/// Which source the words should come from, after MeloX's `LyricSourcePreference`: `automatic` asks
/// every source and ranks by quality, while a named source uses only that one. Doni adds `lrclib` to
/// the reference's three because it keeps LRCLIB in the chain. NetEase is always queried, since AMLL
/// is keyed by its song ID.
public enum LyricSourcePreference: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case automatic
    case amll
    case netease
    case qqMusic
    case lrclib

    public var id: String { rawValue }

    public var usesAMLL: Bool { self == .automatic || self == .amll }
    public var usesQQ: Bool { self == .automatic || self == .qqMusic }
    public var usesLRCLIB: Bool { self == .automatic || self == .lrclib }
}

public struct LyricSongMetadata: Hashable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let durationSeconds: Int

    public init(title: String, artist: String, album: String = "",
                durationSeconds: Int) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = max(0, durationSeconds)
    }
}

public struct NetEaseLyricPayload: Codable, Equatable, Sendable {
    public let yrc: String?
    public let lrc: String?
    public let translatedYRC: String?
    public let translatedLRC: String?
    public let romanizedYRC: String?
    public let romanizedLRC: String?
    public let isPureMusic: Bool

    public init(yrc: String?, lrc: String?, translatedYRC: String?,
                translatedLRC: String?, romanizedYRC: String?,
                romanizedLRC: String?, isPureMusic: Bool) {
        self.yrc = yrc
        self.lrc = lrc
        self.translatedYRC = translatedYRC
        self.translatedLRC = translatedLRC
        self.romanizedYRC = romanizedYRC
        self.romanizedLRC = romanizedLRC
        self.isPureMusic = isPureMusic
    }
}

public struct QQLyricPayload: Codable, Equatable, Sendable {
    public let verbatim: String?
    public let lineSynchronized: String?
    public let translation: String?
    public let romanization: String?

    public init(verbatim: String?, lineSynchronized: String?,
                translation: String?, romanization: String?) {
        self.verbatim = verbatim
        self.lineSynchronized = lineSynchronized
        self.translation = translation
        self.romanization = romanization
    }
}

public struct LyricRawSources: Equatable, Sendable {
    public let amllTTML: String?
    public let netEase: NetEaseLyricPayload?
    public let qq: QQLyricPayload?
    public let lrclib: LyricText?

    public init(amllTTML: String?, netEase: NetEaseLyricPayload?,
                qq: QQLyricPayload?, lrclib: LyricText?) {
        self.amllTTML = amllTTML
        self.netEase = netEase
        self.qq = qq
        self.lrclib = lrclib
    }
}

public enum LyricsPayload: Equatable, Sendable {
    case amll(String)
    case netEase(NetEaseLyricPayload)
    case qq(QQLyricPayload, duetReferenceLRC: String?)
    case lrclib(LyricText)
    case pureMusic
}

public enum LyricsFetchOutcome: Equatable, Sendable {
    case sources(LyricRawSources)
    case none
    case failed
}

enum LyricSourceError: Error {
    case invalidResponse
    case noLyrics
}
