import Foundation
import Testing
@testable import Support

@Suite("Lyric provider matching")
struct LyricProviderTests {
    @Test("an exact title and duration match wins")
    func candidateMatching() {
        let song = LyricSongMetadata(title: "晴天", artist: "周杰倫",
                                     album: "葉惠美", durationSeconds: 269)
        let candidates = [
            LyricCandidate(title: "不相关的歌", artist: "someone", album: "",
                           durationSeconds: 269),
            LyricCandidate(title: "晴天", artist: "周杰倫", album: "葉惠美",
                           durationSeconds: 269),
        ]
        #expect(LyricCandidateMatcher.bestCandidate(in: candidates, for: song) == 1)
    }

    @Test("a wrong duration is not rescued by a matching title")
    func durationRejectsWrongSong() {
        let song = LyricSongMetadata(title: "晴天", artist: "周杰倫",
                                     album: "葉惠美", durationSeconds: 269)
        let candidate = LyricCandidate(title: "晴天", artist: "周杰伦",
                                       album: "叶惠美", durationSeconds: 400)
        #expect(LyricCandidateMatcher.bestCandidate(in: [candidate], for: song) == nil)
    }

    @Test("NetEase search responses use both its artist and duration spellings")
    func netEaseSearchDecoding() throws {
        let data = Data(#"""
        {"result":{"songs":[{"id":3453304463,"name":"降温",
        "artists":[{"name":"Zzh"}],"album":{"name":"降温"},"duration":199229}]}}
        """#.utf8)
        let response = try JSONDecoder().decode(NetEaseSearchResponse.self, from: data)
        let candidate = try #require(NetEaseLyricsClient.candidates(in: response).first)
        #expect(candidate.id == 3453304463)
        #expect(candidate.artist == "Zzh")
        #expect(candidate.album == "降温")
        #expect(candidate.durationSeconds == 199)
    }

    @Test("rich provider payloads survive the disk cache")
    func cacheRoundTrip() {
        let netEase = NetEaseLyricPayload(
            yrc: "[0,1000,0](0,500,0)a", lrc: "[00:00.00]a",
            translatedYRC: nil, translatedLRC: "[00:00.00]b",
            romanizedYRC: nil, romanizedLRC: nil, isPureMusic: false
        )
        let qq = QQLyricPayload(verbatim: "[0,1000]a(0,500)b",
                                lineSynchronized: "[00:00.00]a",
                                translation: "[00:00.00]b",
                                romanization: nil)
        let payloads = [
            LyricsPayload.amll("<tt><body><p begin=\"1s\" end=\"3s\">x</p></body></tt>"),
            .netEase(netEase),
            .qq(qq, duetReferenceLRC: "[00:00.00]duet"),
            .lrclib(.synced("[00:01.00]x")),
            .lrclib(.plain("x")),
            .pureMusic,
        ]
        for payload in payloads {
            #expect(LyricsCacheCodec.decode(LyricsCacheCodec.encode(payload)) == payload)
        }
    }
}
