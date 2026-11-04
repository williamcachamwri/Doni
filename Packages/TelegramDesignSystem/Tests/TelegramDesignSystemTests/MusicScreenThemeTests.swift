import SwiftUI
import Testing
@testable import TelegramDesignSystem

/// The MeloX numbers are transcriptions, so these tests only hold the parts that are derived — a
/// sum or a relationship the reference states in two places — and catch a token that gets edited
/// instead of re-measured.
@Suite("MusicScreenTheme")
struct MusicScreenThemeTests {
    @Test("the mini player's height is its artwork plus the two vertical pads")
    func miniPlayerHeight() {
        #expect(MusicMiniPlayerMetrics.art == 40)
        #expect(MusicMiniPlayerMetrics.artRadius == 6)
        #expect(MusicMiniPlayerMetrics.verticalPadding == 6)
        #expect(MusicMiniPlayerMetrics.height == 52)
        #expect(MusicMiniPlayerMetrics.height
                == MusicMiniPlayerMetrics.art + 2 * MusicMiniPlayerMetrics.verticalPadding)
    }

    @Test("the now-playing overlay is its utility band plus its core")
    func nowPlayingOverlayHeights() {
        #expect(MusicNowPlayingMetrics.utilityHeight == 62)
        #expect(MusicNowPlayingMetrics.coreHeight == 279)
        #expect(MusicNowPlayingMetrics.overlayHeight == 341)
        #expect(MusicNowPlayingMetrics.overlayHeight
                == MusicNowPlayingMetrics.utilityHeight + MusicNowPlayingMetrics.coreHeight)
    }

    @Test("the core's four layers fill the core exactly")
    func coreLayersSum() {
        let total = MusicNowPlayingMetrics.progressHeight
            + MusicNowPlayingMetrics.progressToTransport
            + MusicNowPlayingMetrics.transportRowHeight
            + MusicNowPlayingMetrics.transportToVolume
            + MusicNowPlayingMetrics.volumeHeight
            + MusicNowPlayingMetrics.volumeToSelector
            + MusicNowPlayingMetrics.selectorHeight
        #expect(abs(total - MusicNowPlayingMetrics.coreHeight) < 0.001)
    }

    @Test("artwork sizing reserves the core and the room above it")
    func artworkReserve() {
        // A page of height h gets min(w + 16, max(170, h − 279 − 92)); 541 is the height at which
        // the free space exactly meets the 170 floor, so anything shorter starts clipping to it.
        #expect(MusicNowPlayingMetrics.artworkMin == 170)
        #expect(MusicNowPlayingMetrics.artworkReserve == 92)
        #expect(MusicNowPlayingMetrics.artworkMin + MusicNowPlayingMetrics.coreHeight
                + MusicNowPlayingMetrics.artworkReserve == 541)
        #expect(MusicNowPlayingMetrics.pausedArtworkScale == 0.74)
        #expect(MusicNowPlayingMetrics.artworkRadius == 12)
    }

    @Test("the page-selector row keeps its own gutter inside the 32 pt page padding")
    func selectorInsets() {
        #expect(MusicNowPlayingMetrics.horizontal == 32)
        #expect(MusicNowPlayingMetrics.selectorHeight == 50)
        #expect(MusicNowPlayingMetrics.selectorButton == 44)
        #expect(MusicNowPlayingMetrics.badgeSize == 15)
    }

    @Test("the interface stagger is four layers, fanning out going in and folding back coming out")
    func layerStagger() {
        #expect(MusicMotion.layerShowDelays == [0.025, 0.05, 0.075, 0.10])
        #expect(MusicMotion.layerHideDelays == [0.075, 0.05, 0.025, 0.0])
        // Each layer's two delays share one 0.10 s window: a layer that enters last leaves first.
        for (show, hide) in zip(MusicMotion.layerShowDelays, MusicMotion.layerHideDelays) {
            #expect(abs(show + hide - 0.10) < 0.0001)
        }
        #expect(MusicMotion.progressHiddenOffset == 180)
        #expect(MusicMotion.transportHiddenOffset == 165)
        #expect(MusicMotion.volumeHiddenOffset == 148)
        #expect(MusicMotion.selectorHiddenOffset == 128)
        #expect(MusicMotion.utilityHiddenOffset == 64)
        #expect(MusicMotion.utilityHiddenScale == 0.82)
    }

    @Test("the feed's rhythm is one gutter wide and the shelf breathes by 14")
    func feedRhythm() {
        #expect(MusicFeedMetrics.gutter == 16)
        #expect(MusicFeedMetrics.sectionSpacing == 32)
        #expect(MusicFeedMetrics.sectionSpacing == 2 * MusicFeedMetrics.gutter)
        #expect(MusicFeedMetrics.headerToShelf == 14)
        #expect(MusicFeedMetrics.shelfSpacing == 14)
        #expect(MusicFeedMetrics.playlistCard == 166)
        #expect(MusicFeedMetrics.songCard == 154)
        #expect(MusicFeedMetrics.cardTextGap == 8)
    }

    @Test("the quick-action tiles are one height and six gradient pairs")
    func quickActions() {
        #expect(MusicQuickActionMetrics.compactHeight == 132)
        #expect(MusicQuickActionMetrics.compactWidth == 230)
        #expect(MusicQuickActionMetrics.radius == 14)
        #expect(MusicQuickActionMetrics.gap == MusicFeedMetrics.gutter)
        #expect(MusicQuickActionMetrics.gradientPairs.count == 6)
        #expect(MusicQuickActionMetrics.gradientPairs.allSatisfy { $0.from != $0.to })
    }

    @Test("the settings card's rule starts short of where its text does")
    func settingsCard() {
        #expect(MusicSettingsMetrics.cardRadius == 26)
        #expect(MusicSettingsMetrics.rowMinHeight == 68)
        // 18 of row padding, a 30 pt icon column and 14 pt of gap put the text at 62; the rule is
        // drawn four short of it.
        #expect(MusicSettingsMetrics.rowPaddingH + MusicSettingsMetrics.rowIconWidth
                + MusicSettingsMetrics.rowIconGap == 62)
        #expect(MusicSettingsMetrics.dividerLeading == 58)
        #expect(MusicSettingsMetrics.headerToCard == 10)
        #expect(MusicSettingsMetrics.headerPadding == 14)
    }

    @Test("the playlist hero stacks its own gutters under the artwork")
    func playlistHero() {
        #expect(MusicPlaylistMetrics.heroArtRadius == 12)
        #expect(MusicPlaylistMetrics.heroShadowRadius == 18)
        #expect(MusicPlaylistMetrics.heroShadowY == 10)
        #expect(MusicPlaylistMetrics.heroSidePadding == 24)
        #expect(MusicPlaylistMetrics.heroTop == 26)
        #expect(MusicPlaylistMetrics.heroArtToTitle == 24)
        #expect(MusicPlaylistMetrics.heroToActions == 17)
        #expect(MusicPlaylistMetrics.actionGap == MusicFeedMetrics.shelfSpacing)
        #expect(MusicPlaylistMetrics.addArt == 52)
        #expect(MusicPlaylistMetrics.rowArt == 54)
    }

    @Test("the artwork radius walks up through the surfaces it lands on")
    func artworkRadii() {
        #expect(MusicMiniPlayerMetrics.artRadius == 6)
        #expect(MusicPlaylistMetrics.trackArtRadius == 6)
        #expect(MusicPlaylistMetrics.rowArtRadius == 7)
        #expect(MusicPlaylistMetrics.addArtRadius == 7)
        #expect(MusicArtworkMetrics.radius == 10)
        #expect(MusicNowPlayingMetrics.artworkRadius == 12)
        #expect(MusicQuickActionMetrics.radius == 14)
    }

    @Test("the settlement horizons sit above the curves they wait out")
    func settlement() {
        // The overdamped 1/350/40 spring settles in about 0.5845 s; the coordinator's own
        // horizons are shorter because they wait out a page, not the spring's tail.
        #expect(MusicMotion.pageSpringSettling > 0.58)
        #expect(MusicMotion.pageSpringSettling < 0.59)
        #expect(MusicMotion.settleStandard == 0.50)
        #expect(MusicMotion.settleDirectAlternate == 0.46)
        #expect(MusicMotion.settleHiddenQueue == 0.42)
        #expect(MusicMotion.settleStandard > MusicMotion.settleDirectAlternate)
        #expect(MusicMotion.settleDirectAlternate > MusicMotion.settleHiddenQueue)
    }

    @Test("the queue's pills are capsules and its rows keep the mini player's radius")
    func queue() {
        #expect(MusicQueueMetrics.pillHeight == 44)
        #expect(MusicQueueMetrics.pillRadius == MusicQueueMetrics.pillHeight / 2)
        #expect(MusicQueueMetrics.rowArt == MusicPlaylistMetrics.trackArt)
        #expect(MusicQueueMetrics.rowArtRadius == MusicMiniPlayerMetrics.artRadius)
        #expect(MusicQueueMetrics.rowArt == 48)
    }

    @Test("the tint is the system red the dark scheme resolves to")
    func tint() {
        let red = SRGBComponents(rgb: MusicTint.accentRGB)
        #expect(red.red == 1.0)
        #expect(abs(red.green - 0x45 / 255.0) < 0.0001)
        #expect(abs(red.blue - 0x3a / 255.0) < 0.0001)
    }
}
