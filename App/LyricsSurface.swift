import DoniLyrics
import Foundation
import SwiftUI
import TelegramDesignSystem

/// The words page: the reference's column, with room kept free above it for the panel's header
/// (`NowPlayingLyricsPage.swift:60-76`, `:148-154`).
/// The column is a viewport holding the sung line a quarter down it, so an unreserved header pushes the
/// fade onto the transport buttons and starts the words under the grip.
struct LyricsPage: View {
    @ObservedObject var player: Player
    @ObservedObject var lyrics: Lyrics
    let isInterfaceHidden: Bool
    let onInterfaceInteraction: () -> Void
    let onInterfaceVisibilityChange: (Bool) -> Void

    var body: some View {
        LyricsView(player: player, lyrics: lyrics, isInterfaceHidden: isInterfaceHidden,
                   onInterfaceInteraction: onInterfaceInteraction,
                   onInterfaceVisibilityChange: onInterfaceVisibilityChange)
            // The panel draws the header over this page, so the column only reserves its room: 72 pt
            // of header plus the 16 under it (`NowPlayingLyricsPage.swift:70`, `:148-154`).
            .padding(.top, MusicNowPlayingMetrics.lyricsHeaderSide
                            + MusicNowPlayingMetrics.lyricsColumnGap)
            .padding(.bottom, MusicNowPlayingMetrics.lyricsBottomInset)
    }
}

/// The column itself: `AppleMusicLyricsView`, copied line for line for its scroll, focus cascade,
/// per-line glow and tap-to-seek. Only its inputs are Doni's — this song's lines, plus a `PlayerStore`
/// mirror, because the copied screen wants an `@Observable` player while Doni's is a `Publisher` one.
///
/// It lives in `App/` rather than `UI/` because both shells draw the same column: the phone's Now
/// Playing page and the desktop's inspector panel and player page. Nothing in it is UIKit.
struct LyricsView: View {
    @ObservedObject var player: Player
    @ObservedObject var lyrics: Lyrics
    var isActive = true
    /// Where the sung line's centre sits, measured from the top of this column. The phone leaves it nil
    /// because its page centres the line a quarter down the viewport; the desktop has to pass the
    /// artwork's own centre, which is the anchor Apple Music puts the focused line on.
    var focusAnchorOffset: CGFloat? = nil
    var isInterfaceHidden = false
    var onInterfaceInteraction: () -> Void = {}
    var onInterfaceVisibilityChange: (Bool) -> Void = { _ in }
    @State private var store = PlayerStore()

    var body: some View {
        AppleMusicLyricsView(
            lyrics: lyrics.lines,
            errorMessage: lyrics.errorMessage,
            highlightedLyricID: nil,
            isActive: isActive,
            isInterfaceHidden: isInterfaceHidden,
            // The transport row floats over this page, so the column has to be told how much of its
            // bottom is not really its bottom: that is where the fade stops and the last line may rest.
            bottomOverlayHeight: MusicNowPlayingMetrics.overlayHeight,
            focusAnchorOffset: focusAnchorOffset,
            onInterfaceInteraction: onInterfaceInteraction,
            onInterfaceVisibilityChange: onInterfaceVisibilityChange,
            onInitialFocusPrepared: nil
        )
        .environment(Lyrics.settings)
        .environment(store)
        .onAppear(perform: publish)
        // The reference's clock: it answers from the last position it was told plus the time since.
        // Four ticks a second from Doni's player would stutter under a screen redrawing at sixty.
        .onChange(of: player.elapsed) { _, seconds in store.progress = seconds }
        .onChange(of: player.isPlaying) { _, playing in
            store.isPlaying = playing
            store.rate = playing ? 1 : 0
        }
        .onChange(of: player.current?.uniqueId) { _, _ in publish() }
    }

    /// Hand the screen the song it is looking at, and the way back to the player when a line is tapped.
    /// The seek holds the store weakly on purpose: the store owns the closure, so a strong `self` is a
    /// cycle the panel would never break.
    private func publish() {
        store.currentSong = player.current.map {
            Song(
                id: $0.uniqueId,
                name: $0.displayTitle,
                artistText: $0.displayPerformer,
                album: Album(artworkURL: $0.localPath.map { URL(fileURLWithPath: $0) }),
                shareURL: $0.localPath.map { URL(fileURLWithPath: $0) }
                    ?? URL(string: "https://t.me/")!
            )
        }
        store.progress = player.elapsed
        store.isPlaying = player.isPlaying
        store.rate = player.isPlaying ? 1 : 0
        store.onSeek = { [weak store, player] seconds in
            player.seek(to: seconds)
            store?.seekRevision += 1
        }
    }
}
