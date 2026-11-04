import Foundation
import Testing
@testable import Support

/// The LRC rules are small, and every one of them is a way a real file breaks a naive reader.
@Suite("LRCParser")
struct LRCParserTests {
    @Test("a line is on screen from its own stamp until the next one's")
    func spans() {
        let lines = LRCParser.lines("""
        [00:10.00]first
        [00:20.50]second
        """)
        #expect(lines.count == 2)
        #expect(lines[0].start == 10)
        #expect(lines[0].end == 20.5)
        // The last line has no next one to end it, and a song that ends mid-lyric is not the lyric's
        // fault: it stays on screen.
        #expect(lines[1].end == .infinity)
        #expect(lines[0].contains(19.9))
        #expect(!lines[0].contains(20.5))
    }

    @Test("several stamps on one line are the same words sung again")
    func repeated() {
        let lines = LRCParser.lines("[00:05.00][01:30.00]chorus")
        #expect(lines.count == 2)
        #expect(lines.map(\.start) == [5, 90])
        #expect(lines.map(\.text) == ["chorus", "chorus"])
    }

    @Test("nothing in the format says the file is in order")
    func sorted() {
        let lines = LRCParser.lines("""
        [00:40.00]late
        [00:10.00]early
        """)
        #expect(lines.map(\.text) == ["early", "late"])
        #expect(lines[0].end == 40)
    }

    @Test("the offset tag moves every timestamp, and is not a line")
    func offset() {
        let lines = LRCParser.lines("""
        [offset:-500]
        [00:10.00]ten
        """)
        #expect(lines.count == 1)
        #expect(lines[0].start == 9.5)
    }

    @Test("metadata tags are skipped rather than sung")
    func metadata() {
        let lines = LRCParser.lines("""
        [ti:Title]
        [ar:Artist]
        [by:Someone]
        [al:Album]
        [00:12.345]word
        """)
        #expect(lines.count == 1)
        // A three-digit fraction is milliseconds, not a tenth.
        #expect(abs(lines[0].start - 12.345) < 0.0001)
    }

    @Test("a blank or unmarked line is not a lyric")
    func blanks() {
        #expect(LRCParser.lines("just words, no stamps").isEmpty)
        #expect(LRCParser.lines("[00:01.00]   ").isEmpty)
        #expect(LRCParser.lines("[00:01.00]a\n\n[00:02.00]b").count == 2)
    }

    @Test("times that are not times are refused, not read as zero")
    func malformed() {
        #expect(LRCParser.timestamp("01:23") == 83)
        #expect(LRCParser.timestamp("1:23.4") == 83.4)
        #expect(LRCParser.timestamp("by:me") == nil)
        #expect(LRCParser.timestamp("70:00") == 4200)
        // A seconds field past 60 is a typo, and a silent 0 would put the line at the top of the song.
        #expect(LRCParser.timestamp("00:75") == nil)
        #expect(LRCParser.timestamp("-5:00") == nil)
    }

    @Test("synced, plain and nothing are three different answers")
    func kinds() {
        #expect(LRCParser.parse(nil) == .none)
        #expect(LRCParser.parse("   ") == .none)
        #expect(LRCParser.parse("hello there") == .plain("hello there"))
        if case .synced(let lines) = LRCParser.parse("[00:01.00]hi") {
            #expect(lines.count == 1)
        } else {
            Issue.record("a stamped file is synced")
        }
        // lrclib sends an empty `syncedLyrics` and a filled `plainLyrics`; the caller asks for the
        // first and has to be handed the second, not an empty scroll.
        #expect(LRCParser.parse("") == .none)
        #expect(LRCParser.parse("[00:00.00]x").lines.count == 1)
    }
}
