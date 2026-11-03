import Foundation
import Testing
@testable import Support

@Suite("SearchHighlight")
struct SearchHighlightTests {
    static func cut(_ text: String, _ query: String) -> [String] {
        SearchHighlight.ranges(of: query, in: text).map { String(text[$0]) }
    }

    @Test("a toneless query cuts the accented run out of the title")
    func accentedRun() {
        #expect(Self.cut("Em ghi điều anh dặn dò", "dieu") == ["điều"])
        #expect(Self.cut("Em ghi điều anh dặn dò", "dan do") == ["dặn dò"])
        #expect(Self.cut("Tương Tư À", "tuong tu") == ["Tương Tư"])
    }

    @Test("every occurrence is cut, in order")
    func allOccurrences() {
        #expect(Self.cut("nhạc remix nhạc remix", "nhac") == ["nhạc", "nhạc"])
        #expect(Self.cut("Nonstop Trend 2026", "2026") == ["2026"])
    }

    @Test("runs of whitespace collapse the same way the matcher does")
    func collapsedSpacing() {
        #expect(Self.cut("Em   với   anh", "em voi anh") == ["Em   với   anh"])
        #expect(Self.cut("  Hạt Mưa  ", "hat mua") == ["Hạt Mưa"])
    }

    @Test("nothing is cut for an empty or absent query")
    func nothing() {
        #expect(Self.cut("Điều", "").isEmpty)
        #expect(Self.cut("Điều", "   ").isEmpty)
        #expect(Self.cut("Điều", "meo").isEmpty)
    }

    @Test("segments rebuild the original, matched halves flagged")
    func segments() {
        let parts = SearchHighlight.segments(of: "remix", in: "Hạt Mưa Vương Vấn Remix")
        #expect(parts.map(\.text) == ["Hạt Mưa Vương Vấn ", "Remix"])
        #expect(parts.map(\.isMatch) == [false, true])
        #expect(parts.map(\.text).joined() == "Hạt Mưa Vương Vấn Remix")
    }
}
