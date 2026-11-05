import Foundation
import Testing
@testable import Support

/// The parts of a network lookup that can be wrong before a byte is sent: the address, the shape of
/// the answer, and the order the answers are preferred in.
@Suite("LRClib")
struct LRClibTests {
    private let query = LyricQuery(artist: "Sơn Tùng M-TP",
                                   title: "Chúng Ta Của Hiện Tại", duration: 253)

    @Test("a Vietnamese title survives the trip through a URL")
    func encoding() throws {
        let url = try #require(LRClib.getURL(query))
        #expect(url.path == "/api/get")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains { $0.name == "track_name" && $0.value == "Chúng Ta Của Hiện Tại" })
        #expect(items.contains { $0.name == "artist_name" && $0.value == "Sơn Tùng M-TP" })
        #expect(items.contains { $0.name == "duration" && $0.value == "253" })
        // What actually goes on the wire, not what the components claim.
        let absolute = url.absoluteString
        #expect(!absolute.contains(" "), "percent-encoded: \(absolute)")
        #expect(absolute.contains("%"), "the diacritics are encoded, not sent raw")
        #expect(!absolute.contains("Sơn"), "no raw Vietnamese: \(absolute)")
    }

    @Test("the file's size is not sent")
    func leastData() {
        let absolute = LRClib.getURL(query)?.absoluteString ?? ""
        #expect(!absolute.contains("file_size"), "\(absolute)")
        #expect(!absolute.contains("album"), "\(absolute)")
    }

    @Test("an empty query is no query")
    func empty() {
        #expect(LRClib.searchURL(LyricQuery(artist: "", title: "", duration: 0)) == nil)
        // `/api/get` with nothing to match on would ask the site for its whole catalogue.
        #expect(LRClib.getURL(LyricQuery(artist: "", title: "", duration: 0)) != nil)
    }

    @Test("the upload's bitrate is not part of the song's name")
    func titlesDropUploadNoise() {
        let query = LyricQuery(artist: "",
                               title: "LAVIAI (REMIX) ft. HIEUTHUHAI & 2PILLZ (320kbps)",
                               duration: 205)
        #expect(LRClib.titles(for: query) == [
            query.title,
            "LAVIAI (REMIX) ft. HIEUTHUHAI & 2PILLZ",
        ])
    }

    @Test("a remix tag is the song, a bitrate is the file")
    func cleaningKeepsWhatMatters() {
        let query = LyricQuery(artist: "Wxrdie",
                               title: "LAVIAI [320 Kbps] [Official Audio].mp3", duration: 205)
        #expect(LRClib.titles(for: query).last == "LAVIAI [Official Audio]")
    }

    @Test("both answer shapes decode, because the two endpoints do not agree")
    func shapes() throws {
        let one = Data(#"{"id":1,"name":"x","syncedLyrics":"[00:01.00]a","plainLyrics":""}"#
            .utf8)
        #expect(LRClib.entries(one).count == 1)

        let many = Data(#"[{"syncedLyrics":"","plainLyrics":"words"},{"syncedLyrics":"","plainLyrics":"more"}]"#
            .utf8)
        #expect(LRClib.entries(many).count == 2)

        #expect(LRClib.entries(Data("not json".utf8)).isEmpty)
        // A field list that grows upstream must not turn a working lookup into a decode failure.
        let extra = Data(#"{"syncedLyrics":"[00:02.00]b","plainLyrics":"","id":7,"instrumentational":false}"#
            .utf8)
        #expect(LRClib.entries(extra).first?.syncedLyrics == "[00:02.00]b")
    }

    @Test("synced beats plain, and an empty field is not a lyric")
    func preference() {
        let both = [LRClib.Entry(syncedLyrics: "[00:01.00]one", plainLyrics: "unone")]
        // The text is handed over unparsed: reading stamps is the lyrics screen's job.
        #expect(LRClib.text(of: both) == .synced("[00:01.00]one"))

        // lrclib sends "" for a field the lyric does not have — the trap this whole file exists for.
        let onlyPlain = [LRClib.Entry(syncedLyrics: "", plainLyrics: "just words")]
        #expect(LRClib.text(of: onlyPlain) == .plain("just words"))

        let nothing = [LRClib.Entry(syncedLyrics: "", plainLyrics: "   ")]
        #expect(LRClib.text(of: nothing) == .none)

        // A first answer with no timed line must not hide the second one's.
        let two = [LRClib.Entry(syncedLyrics: "", plainLyrics: "a"),
                   LRClib.Entry(syncedLyrics: "[00:05.00]b", plainLyrics: "c")]
        #expect(LRClib.text(of: two) == .synced("[00:05.00]b"))
    }
}
