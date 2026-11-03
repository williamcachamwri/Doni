import Testing
import Foundation
@testable import TelegramDesignSystem

/// The login motion tokens are transcriptions of specific animation calls in the reference, so
/// they are asserted against the numbers those calls produce rather than against a feeling.
@Suite("Login motion")
struct TelegramLoginMotionTests {
    @Test("The wrong-code shake is the keyframe track addShakeAnimation builds")
    func codeShakeTrack() {
        // amplitude -30, count 6, decay: 0, then -30·sign/(i+1), then back to 0.
        #expect(TelegramLoginMotion.codeShake == [0, -30, 15, -10, 7.5, -6, 5, 0])

        let samples: [(Double, CGFloat)] = [
            (0.0, 0), (1.0 / 7.0, -30), (2.0 / 7.0, 15), (3.0 / 7.0, -10),
            (4.0 / 7.0, 7.5), (5.0 / 7.0, -6), (6.0 / 7.0, 5), (1.0, 0)
        ]
        for (at, expected) in samples {
            let value = TelegramLoginMotion.shakeOffset(at: at, offsets: TelegramLoginMotion.codeShake)
            #expect(abs(value - expected) < 0.0001, "offset at progress \(at)")
        }
    }

    @Test("A word or phrase field shakes with the helper's own defaults")
    func wordShakeTrack() {
        #expect(TelegramLoginMotion.wordShake == [0, 3, -3, 3, -3, 0])
        #expect(
            abs(TelegramLoginMotion.shakeOffset(at: 0.4, offsets: TelegramLoginMotion.wordShake) + 3) < 0.0001
        )
    }

    @Test("A progress outside the track holds the ends")
    func clamped() {
        #expect(TelegramLoginMotion.shakeOffset(at: -1, offsets: TelegramLoginMotion.codeShake) == 0)
        #expect(TelegramLoginMotion.shakeOffset(at: 4, offsets: TelegramLoginMotion.codeShake) == 0)
        #expect(TelegramLoginMotion.shakeOffset(at: 0.5, offsets: []) == 0)
    }

    @Test("The error line steps out 13 pt once the screen is wider than 320 pt")
    func errorOffset() {
        #expect(TelegramLoginMotion.errorOffset(screenWidth: 320) == 11)
        #expect(TelegramLoginMotion.errorOffset(screenWidth: 375) == 24)
        #expect(TelegramLoginMotion.errorOffset(screenWidth: 430) == 24)
    }

    @Test("The snapshot hand-over throws the text higher than the field")
    func handOver() {
        #expect(TelegramLoginMotion.ghostTextOffset == -140)
        #expect(TelegramLoginMotion.ghostFieldOffset == -100)
        #expect(TelegramLoginMotion.ghostFieldScale == 0.3)
        #expect(TelegramLoginMotion.failedResetDelay == 0.85)
    }
}
