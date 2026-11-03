import Testing
@testable import TelegramDesignSystem

@Suite("SRGBComponents")
struct SRGBComponentsTests {
    @Test("splits 0xRRGGBB into the right bytes")
    func splitsBytes() {
        let grey = SRGBComponents(rgb: 0x8e8e93)
        #expect(grey.red == 142.0 / 255.0)
        #expect(grey.green == 142.0 / 255.0)
        #expect(grey.blue == 147.0 / 255.0)
        #expect(grey.alpha == 1.0)

        let accent = SRGBComponents(rgb: 0x0088ff)
        #expect(accent.red == 0.0)
        #expect(accent.blue == 1.0)
        #expect(SRGBComponents(rgb: 0xffffff).green == 1.0)
        #expect(SRGBComponents(rgb: 0x000000).blue == 0.0)
    }

    @Test("alpha is carried through, not multiplied into the channels")
    func alpha() {
        let blurred = SRGBComponents(rgb: 0xf2f2f2, alpha: 0.9)
        #expect(blurred.alpha == 0.9)
        #expect(blurred.red == 242.0 / 255.0)
    }

    /// Guards the documented derivation in Docs/design-tokens.md: Telegram's
    /// opaque nav background is `0xf7f7f7` mixed with white at 0.14, i.e. 248.
    @Test("mixed nav background resolves to the documented byte")
    func mixedNavBackground() {
        let base = SRGBComponents(rgb: 0xf7f7f7)
        let mixed = base.red * 0.86 + 1.0 * 0.14
        #expect((mixed * 255.0).rounded() == 248.0)
    }
}
