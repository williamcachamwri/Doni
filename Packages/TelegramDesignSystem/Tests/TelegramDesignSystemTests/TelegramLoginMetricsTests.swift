import Foundation
import Testing
@testable import TelegramDesignSystem

/// The code row is the one part of the sequence that is made of fixed squares, so it is the part
/// that can be wider than the phone holding it. These are the numbers it has to respect.
@Suite("Login metrics")
struct TelegramLoginMetricsTests {
    private let spacing = TelegramLoginMetrics.codeBoxSpacing

    private func row(_ digits: Int, _ width: CGFloat) -> CGFloat {
        CGFloat(digits) * width + CGFloat(digits - 1) * spacing
    }

    @Test("the reference's full boxes are used whenever the band really fits them")
    func fullSizeWhenItFits() {
        // A 390 pt phone has 342 pt of band, and six 43 pt boxes with 15 between them are 333.
        #expect(TelegramLoginMetrics.fitCodeBoxWidth(digits: 5, available: 342)
            == TelegramLoginMetrics.codeBoxWidth)
        #expect(TelegramLoginMetrics.fitCodeBoxWidth(digits: 6, available: 342)
            == TelegramLoginMetrics.codeBoxWidth)
        #expect(row(6, TelegramLoginMetrics.codeBoxWidth) <= 342)
    }

    @Test("a row that does not fit drops to the compact boxes, and below them if need be")
    func compactWhenItDoesNot() {
        // Seven 43 pt boxes are 391 pt, seven 37 pt ones are 349: between those two widths the
        // compact row is the answer.
        #expect(TelegramLoginMetrics.fitCodeBoxWidth(digits: 7, available: 360)
            == TelegramLoginMetrics.codeBoxCompactWidth)
        // Past it, the boxes share the band instead of drawing over both edges of the phone.
        let narrowed = TelegramLoginMetrics.fitCodeBoxWidth(digits: 7, available: 342)
        #expect(narrowed < TelegramLoginMetrics.codeBoxCompactWidth)
        #expect(row(7, narrowed) <= 342)
    }

    @Test("whatever the digit count and the band, the row is never wider than the band")
    func neverOverflows() {
        for available in [296.0, 342.0, 375.0, 430.0] {
            for digits in 4...10 {
                let width = TelegramLoginMetrics.fitCodeBoxWidth(digits: digits, available: available)
                #expect(width > 0, "\(digits) digits at \(available) pt")
                #expect(row(digits, width) <= available + 0.001,
                        "\(digits) boxes of \(width) pt in a \(available) pt band")
            }
        }
    }

    @Test("an empty band is still a row of boxes, not a zero or a negative width")
    func degenerate() {
        #expect(TelegramLoginMetrics.fitCodeBoxWidth(digits: 6, available: 0) == 12)
        #expect(TelegramLoginMetrics.fitCodeBoxWidth(digits: 0, available: 342)
            == TelegramLoginMetrics.codeBoxWidth)
    }
}
