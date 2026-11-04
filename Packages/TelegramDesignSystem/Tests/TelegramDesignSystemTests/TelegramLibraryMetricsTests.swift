import SwiftUI
import Testing
@testable import TelegramDesignSystem

@Suite("TelegramLibraryMetrics")
struct TelegramLibraryMetricsTests {
    @Test("the scale is the app's own, which is the source's default")
    func scale() {
        // The list was first drawn at the reference phone's `extraSmall` (base 14); the user
        // directed it larger, so the app sits at the source's own 17 and every ratio is kept.
        #expect(TelegramLibraryMetrics.base == 17)
        #expect(TelegramLibraryMetrics.scaled(16) == 16)
        #expect(TelegramLibraryMetrics.scaled(15) == 15)
        #expect(TelegramLibraryMetrics.scaled(14) == 14)
        #expect(TelegramLibraryMetrics.scaled(12) == 12)
        #expect(TelegramLibraryMetrics.scaled(20) == 20)
        #expect(TelegramLibraryMetrics.scaled(60) == 60)
        #expect(TelegramLibraryMetrics.scaled(8) == 8)
    }

    @Test("the art tile is the chat list's own icon slot, centred in the cell")
    func artTile() {
        #expect(TelegramLibraryMetrics.artSide == 60)
        // `floor((itemHeight − diameter) / 2)`, the way the avatar sits (`ChatListItem.swift:4208`).
        #expect(TelegramLibraryMetrics.artTop == 6)
        // `avatarLeftInset = 24 + diameter` (`:2574`) plus the 2 pt the content rect carries
        // (`:4054`): the text column begins at 86.
        #expect(TelegramLibraryMetrics.textColumnLeft == 86)
        #expect(TelegramLibraryMetrics.leading + TelegramLibraryMetrics.artSide
            + TelegramLibraryMetrics.artToText == 86, "the text column still begins where the inset says")
        #expect(TelegramLibraryMetrics.artToText == 10)
    }

    @Test("the row keeps the chat list's own anchors")
    func anchors() {
        // `4L − 8` at the line box of 20.
        #expect(TelegramLibraryMetrics.rowHeight == 72)
        #expect(TelegramLibraryMetrics.titleTop == 8)
        #expect(TelegramLibraryMetrics.dateTop == 10)
        #expect(TelegramLibraryMetrics.titleToPreview == -2)
        #expect(TelegramLibraryMetrics.stateSide == 20)
        #expect(TelegramLibraryMetrics.stateGlyph == 12)
        // The pill is pinned to the bottom of the content rect.
        #expect(abs(TelegramLibraryMetrics.stateTop - 35.0) < 0.01)
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
    @Test("the bar is the pill the device asked for, wrapping the capsule the photo measures")
    func band() {
        // 44 pt of controls (`vedges 100`: 172 → 302 px) with 4 pt of glass above and below.
        #expect(TelegramBarMetrics.contentHeight == 44)
        #expect(TelegramBarMetrics.height == 52)
        #expect(TelegramBarMetrics.sideInset == 16)
        // The pill floats 8 under the safe area and the first row starts 12 under it.
        #expect(TelegramBarMetrics.topClearance
            == TelegramBarMetrics.topGap + TelegramBarMetrics.height
                + TelegramBarMetrics.belowGap)
        #expect(TelegramBarMetrics.topClearance == 72)
    }

    @Test("the bottom chrome is the kit's toolbar over its tab bar")
    func floating() {
        // The toolbar insets 12 from each edge (`AMTabBarController.swift:48-49`) and hangs 6
        // above the tab bar (`:50`).
        #expect(TelegramFloatingBarMetrics.toolbarMargin == 12)
        #expect(TelegramFloatingBarMetrics.toolbarToTabBar == 6)
        // The toolbar is the 56 pt bar whose artwork arithmetic is tested above; the tab bar is
        // the system's 49.
        #expect(TelegramShellMetrics.miniPlayerHeight == 56)
        #expect(TelegramShellMetrics.miniPlayerHeight
            == TelegramShellMetrics.miniPlayerArt + 2 * 8)
        #expect(TelegramShellMetrics.tabBarHeight == 49)
    }

    @Test("a list ends above the glass it scrolls under")
    func clearance() {
        // The tab bar's 49 alone, plus toolbar and gap once the strip is up: 49 + 56 + 6.
        #expect(TelegramFloatingBarMetrics.clearance(stripVisible: false) == 49)
        #expect(TelegramFloatingBarMetrics.clearance(stripVisible: true) == 111)
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
