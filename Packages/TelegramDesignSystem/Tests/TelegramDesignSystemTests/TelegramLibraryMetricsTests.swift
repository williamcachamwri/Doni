import SwiftUI
import Testing
@testable import TelegramDesignSystem

@Suite("TelegramLibraryMetrics")
struct TelegramLibraryMetricsTests {
    @Test("the scale is the phone's, not the source default")
    func scale() {
        // The photo that is the parity oracle measures a 56 pt pitch, a 49 pt icon and a 13 pt
        // title, which is Telegram's `extraSmall`; the source files are written at 17.
        #expect(TelegramLibraryMetrics.base == 14)
        #expect(TelegramLibraryMetrics.scaled(16) == 13)
        #expect(TelegramLibraryMetrics.scaled(15) == 12)
        #expect(TelegramLibraryMetrics.scaled(14) == 11)
        #expect(TelegramLibraryMetrics.scaled(12) == 9)
        #expect(TelegramLibraryMetrics.scaled(20) == 16)
        #expect(TelegramLibraryMetrics.scaled(60) == 49)
        #expect(TelegramLibraryMetrics.scaled(8) == 6)
    }

    @Test("the art tile is the chat list's own icon slot, centred in the cell")
    func artTile() {
        #expect(TelegramLibraryMetrics.artSide == 49)
        // `floor((itemHeight − diameter) / 2)`, the way the avatar sits (`ChatListItem.swift:4208`).
        #expect(TelegramLibraryMetrics.artTop == 3)
        // `avatarLeftInset = 24 + diameter` (`:2574`) plus the 2 pt the content rect carries
        // (`:4054`): the text column begins at 75, where the photo measures it.
        #expect(TelegramLibraryMetrics.textColumnLeft == 75)
        #expect(TelegramLibraryMetrics.leading + TelegramLibraryMetrics.artSide
            + TelegramLibraryMetrics.artToText == 75, "the text column still begins where the photo says")
        #expect(TelegramLibraryMetrics.artToText == 10)
    }

    @Test("the row keeps the chat list's own anchors")
    func anchors() {
        // `4L − 8` at the photo's line box of 16.
        #expect(TelegramLibraryMetrics.rowHeight == 56)
        #expect(TelegramLibraryMetrics.titleTop == 6)
        #expect(TelegramLibraryMetrics.dateTop == 8)
        #expect(TelegramLibraryMetrics.titleToPreview == -2)
        #expect(TelegramLibraryMetrics.stateSide == 16)
        #expect(TelegramLibraryMetrics.stateGlyph == 9)
        // The pill is pinned to the bottom of the content rect, 21.7 pt below the row's top.
        #expect(abs(TelegramLibraryMetrics.stateTop - 21.7) < 0.01)
        #expect(TelegramLibraryMetrics.searchFieldHeight == 36)
        #expect(TelegramLibraryMetrics.searchCornerRadius == 10.5)
    }

    @Test("album art is darkened by a quarter of the player's own scrim")
    func scrim() {
        // 0.3 is what `playerAlbumArt` draws under its controls.
        #expect(TelegramLibraryMetrics.artScrim == 0.3 / 4.0)
    }
}

@Suite("TelegramBarMetrics")
struct TelegramBarMetricsTests {
    @Test("the bar is the height the photo measures")
    func band() {
        // 44 pt of capsule (`vedges 100`: 172 → 302 px) with 10 pt above and 12.7 below, the gap to
        // the first row at 113.7 pt.
        #expect(TelegramBarMetrics.capsuleHeight == 44)
        #expect(TelegramBarMetrics.height == 66.7)
        #expect(TelegramBarMetrics.sideInset == 16)
        // One capsule holding three items on a 38.9 pt pitch (`hedges 225`: 773 → 1123 px).
        #expect(TelegramBarMetrics.actionPitch * 3 == TelegramBarMetrics.actionGroupWidth)
    }

    @Test("the floating bar keeps its 20 pt of screen clear on three sides")
    func floating() {
        #expect(TelegramFloatingBarMetrics.margin == 20)
        // 2262 → 2472 px (`vedges 400`).
        #expect(TelegramFloatingBarMetrics.height == 67.3)
        // The search circle is its own glass item: 918 → 1110 px, 8 pt after the capsule.
        #expect(TelegramFloatingBarMetrics.searchCircle == 64)
        #expect(TelegramFloatingBarMetrics.searchCircleGap == 8)
        // Icon ink centred 25.1 pt below the band's top, label ink 50.3.
        #expect(TelegramFloatingBarMetrics.iconCentre < TelegramFloatingBarMetrics.labelCentre)
        #expect(TelegramFloatingBarMetrics.labelCentre < TelegramFloatingBarMetrics.height)
        // The capsule is 278 because the margins and the circle take the rest of the phone.
        #expect(TelegramFloatingBarMetrics.capsuleWidth
            + TelegramFloatingBarMetrics.searchCircleGap
            + TelegramFloatingBarMetrics.searchCircle
            + 2 * TelegramFloatingBarMetrics.margin == 390)
        // Doni's four tabs share the photo's three-item capsule.
        #expect(TelegramFloatingBarMetrics.itemWidth * 4
            == TelegramFloatingBarMetrics.capsuleWidth)
        // The two rows sit on their measured ink centres: the box is centred on each, so the
        // distance from the band's top is the centre minus half the box.
        #expect(abs(TelegramFloatingBarMetrics.iconTop
            - (TelegramFloatingBarMetrics.iconCentre
                - TelegramFloatingBarMetrics.iconBox / 2)) < 0.001)
        #expect(abs(TelegramFloatingBarMetrics.labelTop
            - (TelegramFloatingBarMetrics.labelCentre
                - TelegramFloatingBarMetrics.labelBox / 2)) < 0.001)
        #expect(TelegramFloatingBarMetrics.iconTop
            < TelegramFloatingBarMetrics.labelTop)
    }

    @Test("a list ends above the glass it scrolls under")
    func clearance() {
        // 20 of margin plus 67.3 of band, and 64 + 8 more once the strip is up.
        #expect(abs(TelegramFloatingBarMetrics.clearance(stripVisible: false) - 87.3) < 0.001)
        #expect(abs(TelegramFloatingBarMetrics.clearance(stripVisible: true) - 159.3) < 0.001)
    }
}

@Suite("TelegramTrackGradient")
struct TelegramTrackGradientTests {
    @Test("there are seven gradients, as Telegram lists them")
    func count() {
        #expect(TelegramTrackGradient.pairs.count == 7)
    }

    @Test("the pick is Telegram's: the id's magnitude modulo seven")
    func pick() {
        #expect(TelegramTrackGradient.index(for: 0) == 0)
        #expect(TelegramTrackGradient.index(for: 6) == 6)
        #expect(TelegramTrackGradient.index(for: 7) == 0)
        #expect(TelegramTrackGradient.index(for: 15) == 1)
        #expect(TelegramTrackGradient.index(for: -3) == 3, "a negative chat-side id still picks")
        #expect(TelegramTrackGradient.index(for: .min) == 0, "abs(.min) must not trap")
    }

    @Test("a track always lands on the same colour")
    func stable() {
        for seed in [-900_000, 1, 42, 777_777] {
            let value = Int64(seed)
            #expect(TelegramTrackGradient.index(for: value) == TelegramTrackGradient.index(for: value))
        }
    }
}
