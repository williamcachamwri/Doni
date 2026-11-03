import SwiftUI
import Testing
@testable import TelegramDesignSystem

@Suite("TelegramLibraryMetrics")
struct TelegramLibraryMetricsTests {
    @Test("the art tile is the chat list's own icon slot, centred in the cell")
    func artTile() {
        #expect(TelegramLibraryMetrics.artSide == 54)
        // `floor((itemHeight − diameter) / 2)`, the way the avatar sits (`ChatListItem.swift:4208`).
        #expect(TelegramLibraryMetrics.artTop == 7)
        // `.roundedRect` is `floor(width × 0.25)` (`PeerAvatar.swift:209`).
        #expect(TelegramLibraryMetrics.artRadius == 13)
        #expect(TelegramLibraryMetrics.leading + TelegramLibraryMetrics.artSide
            + TelegramLibraryMetrics.artToText == 84, "the text column still begins at textLeftInset")
    }

    @Test("the row keeps the chat list's own anchors")
    func anchors() {
        #expect(TelegramLibraryMetrics.rowHeight == 68)
        #expect(TelegramLibraryMetrics.titleTop == 8)
        #expect(TelegramLibraryMetrics.dateTop == 10)
        #expect(TelegramLibraryMetrics.titleToPreview == -2)
        #expect(TelegramLibraryMetrics.searchFieldHeight == 36)
        #expect(TelegramLibraryMetrics.searchCornerRadius == 10.5)
    }

    @Test("album art is darkened by a quarter of the player's own scrim")
    func scrim() {
        // 0.3 is what `playerAlbumArt` draws under its controls.
        #expect(TelegramLibraryMetrics.artScrim == 0.3 / 4.0)
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
