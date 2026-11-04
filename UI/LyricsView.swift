import DoniLyrics
import Foundation
import SwiftUI
import TelegramDesignSystem

/// The words page: the reference's column, with the room for the panel's header kept free above it.
///
/// The header is not decoration. The column is a viewport and the line being sung is held a quarter
/// of the way down it, so whatever is above the column pushes the words down and whatever is below
/// them is where they fade out. Give the column the whole panel and the fade lands on the transport
/// buttons and the words start under the grip; reserve the header's 88 pt and the last readable line
/// stops above the controls, which is where the reference puts both
/// (`NowPlayingLyricsPage.swift:60-76`, `:148-154`).
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
            // The header is drawn over this page by the panel, so the column reserves the room for
            // it rather than drawing it — 72 pt of header and the 16 the reference puts under it
            // (`NowPlayingLyricsPage.swift:70`, `:148-154`).
            .padding(.top, MusicNowPlayingMetrics.lyricsHeaderSide
                            + MusicNowPlayingMetrics.lyricsColumnGap)
            .padding(.bottom, MusicNowPlayingMetrics.lyricsBottomInset)
    }
}

/// The column itself.
///
/// The screen is the reference's, line for line: `AppleMusicLyricsView` does the scroll, the focus
/// cascade, the glow that fills each line as it is sung, and the tap-to-seek. What is Doni's is only
/// what it is fed — the lines found for this song, and a mirror of the player for it to watch.
///
/// That mirror exists because the copied screen is written against an `@Observable` player and
/// Doni's is a `Publisher` one, and because the reference interpolates the position between ticks
/// rather than waiting for the next one.
private struct LyricsView: View {
    @ObservedObject var player: Player
    @ObservedObject var lyrics: Lyrics
    let isInterfaceHidden: Bool
    let onInterfaceInteraction: () -> Void
    let onInterfaceVisibilityChange: (Bool) -> Void
    @State private var store = PlayerStore()

    var body: some View {
        AppleMusicLyricsView(
            lyrics: lyrics.lines,
            errorMessage: lyrics.errorMessage,
            highlightedLyricID: nil,
            isActive: true,
            isInterfaceHidden: isInterfaceHidden,
            // The transport row floats over this page rather than taking its own band, so the column
            // has to be told how much of its own bottom is not really its bottom: that is where the
            // fade stops and where the last line is allowed to rest.
            bottomOverlayHeight: MusicNowPlayingMetrics.overlayHeight,
            focusAnchorOffset: nil,
            onInterfaceInteraction: onInterfaceInteraction,
            onInterfaceVisibilityChange: onInterfaceVisibilityChange,
            onInitialFocusPrepared: nil
        )
        .environment(Lyrics.settings)
        .environment(store)
        .onAppear(perform: publish)
        // The reference's own clock: it is asked where the song is, and answers from the last
        // position it was told plus the time that has gone by since. Four ticks a second from
        // Doni's player would be a stutter under a screen that redraws at sixty.
        .onChange(of: player.elapsed) { _, seconds in store.progress = seconds }
        .onChange(of: player.isPlaying) { _, playing in
            store.isPlaying = playing
            store.rate = playing ? 1 : 0
        }
        .onChange(of: player.current?.uniqueId) { _, _ in publish() }
    }

    /// Hand the screen the song it is looking at, and the way back to the player when a line is
    /// tapped.
    ///
    /// The seek closes over the store weakly on purpose: it is the store that holds the closure, and
    /// a strong `self` here is a cycle the panel would never break.
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
