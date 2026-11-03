import Foundation
import Testing
@testable import Support

@Suite("SearchTextFold")
struct SearchTextFoldTests {
    static func assertNormalized(_ input: String, _ expected: String) {
        #expect(SearchTextFold.normalized(input) == expected, "failed for \(input)")
    }

    @Test("acceptance case from the spec")
    func specCase() {
        Self.assertNormalized("Em ghi điều anh dặn dò", "em ghi dieu anh dan do")
        // the unaccented query must fold to the same key as the accented title
        #expect(SearchTextFold.normalized("em ghi dieu anh dan do")
            == SearchTextFold.normalized("Em ghi điều anh dặn dò"))
    }

    @Test("precomposed Vietnamese vowels fold to ASCII")
    func vowels() {
        Self.assertNormalized("Đêm không ngủ được", "dem khong ngu duoc")
        Self.assertNormalized("Tương Tư À", "tuong tu a")
        Self.assertNormalized("ngã tư sở", "nga tu so")
        Self.assertNormalized("ĐẶNG LỆ THU", "dang le thu")
        Self.assertNormalized("Tình yêu là_bản phối lại", "tinh yeu la_ban phoi lai")
    }

    @Test("whitespace collapses, case folds")
    func spacing() {
        Self.assertNormalized("  Em   với \n anh  ", "em voi anh")
        Self.assertNormalized("LỶ LỄ", "ly le")
    }

    @Test("ASCII input is unchanged")
    func plainAscii() {
        Self.assertNormalized("Hello World 123", "hello world 123")
        Self.assertNormalized("", "")
    }

    /// Regression guard for the design decision: if Foundation's folding ever
    /// starts handling `đ`, the transform above becomes redundant and this test
    /// tells us. It documents why `folding` alone is not the implementation.
    @Test("diacritic folding alone is not enough for Vietnamese")
    func foldingAloneIsInsufficient() {
        let folded = ("điều" as NSString).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        #expect(folded != "dieu", "Foundation folding now handles đ; revisit SearchTextFold")
        #expect(folded == "đieu")
    }
}
