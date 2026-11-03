import Foundation
import Testing
@testable import Support

@Suite("TrackFormatting")
struct TrackFormattingTests {
    @Test("binary units with one floored decimal")
    func sizes() {
        #expect(DataSize.string(1_572_864, decimalSeparator: ".") == "1.5 MB")
        // the digit is floored, not rounded: 1.59 MB of bytes still reads 1.5
        #expect(DataSize.string(1_664_614, decimalSeparator: ".") == "1.5 MB")
        #expect(DataSize.string(1_048_576, decimalSeparator: ".") == "1 MB")
        #expect(DataSize.string(900, decimalSeparator: ".") == "900 B")
        #expect(DataSize.string(10_737_418_240, decimalSeparator: ".") == "10 GB")
        #expect(DataSize.string(1024 * 1024 * 1024 + 1024 * 1024 * 512, decimalSeparator: ".") == "1.5 GB")
    }

    /// Telegram takes the separator from the locale, and Vietnamese lists print commas.
    @Test("the decimal separator is the locale's")
    func separator() {
        #expect(DataSize.string(1_572_864, decimalSeparator: ",") == "1,5 MB")
    }

    @Test("duration rolls into hours")
    func durations() {
        #expect(MediaClock.duration(205) == "3:25")
        #expect(MediaClock.duration(60) == "1:00")
        #expect(MediaClock.duration(3_725) == "1:02:05")
        #expect(MediaClock.duration(0) == "0:00")
        #expect(MediaClock.duration(nil) == nil)
        // a document carries no duration at all, and that is not zero seconds
        #expect(MediaClock.duration(-1) == nil)
    }
}
