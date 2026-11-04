import DoniLyrics
import Foundation
import SwiftUI

/// The words, on the panel.
///
/// The screen itself is the reference's, line for line: `AppleMusicLyricsView` does the scroll, the
/// focus cascade, the blur, the glow and the tap-to-seek. What is Doni's is only what it is fed —
/// the lines that were found for the song that is playing, and a mirror of the player for the
/// screen to watch.
///
/// That mirror exists because the copied screen is written against an `@Observable` player and
/// Doni's is a `Publisher` one, and because the reference interpolates the position between ticks
/// rather than waiting for the next one. The mirror is where those two facts meet.
struct LyricsView: View {
    @ObservedObject var player: Player
    @ObservedObject var lyrics: Lyrics
    @State private var store = PlayerStore()

    var body: some View {
        AppleMusicLyricsView(
            lyrics: lyrics.lines,
            errorMessage: lyrics.errorMessage,
            highlightedLyricID: nil,
            isActive: true,
            isInterfaceHidden: false,
            bottomOverlayHeight: 0,
            focusAnchorOffset: nil,
            onInterfaceInteraction: nil,
            onInterfaceVisibilityChange: nil,
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
