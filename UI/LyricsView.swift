import DoniLyrics
import Foundation
import SwiftUI
import TelegramDesignSystem

/// The words page: the reference's header over the reference's column.
///
/// The header is not decoration. The column is a viewport and the line being sung is held a quarter
/// of the way down it, so whatever is above the column pushes the words down and whatever is below
/// them is where they fade out. Give the column the whole panel and the fade lands on the transport
/// buttons; give it the header and the last readable line stops above them, which is what the
/// reference does by wrapping both in one `VStack` (`NowPlayingLyricsPage.swift:60-76`).
struct LyricsPage: View {
    let track: any Playable
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    @ObservedObject var lyrics: Lyrics

    var body: some View {
        VStack(spacing: MusicNowPlayingMetrics.lyricsColumnGap) {
            LyricsSongHeader(track: track, session: session, player: player,
                             artwork: artwork, library: library)

            LyricsView(player: player, lyrics: lyrics)
        }
        .padding(.bottom, MusicNowPlayingMetrics.lyricsBottomInset)
    }
}

/// The 72 pt cover, the song's two lines and the action disc (`NowPlayingSongHeader.swift:65-97`).
///
/// The reference hides the star here and leaves the ellipsis, because the star is already in the
/// transport row — Doni's `SongActions` is that same single disc, so the row is the same row.
struct LyricsSongHeader: View {
    let track: any Playable
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    var body: some View {
        HStack(spacing: MusicNowPlayingMetrics.lyricsHeaderGap) {
            artworkThumb

            VStack(alignment: .leading, spacing: MusicNowPlayingMetrics.titleSpacing) {
                Text(track.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.displayPerformer.isEmpty ? "Doni" : track.displayPerformer)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(MusicNowPlayingMetrics.artistOpacity))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SongActions(track: track, player: player, artwork: artwork, library: library)
        }
        .task(id: track.uniqueId) {
            // The panel asked for the hero tier for the artwork page. A 72 pt thumb is a smaller
            // picture than that, so it is served from what is already held, but the ask is what
            // puts it in the cache when the user went straight to the words.
            await artwork.load(track: track, via: session.covers(),
                               side: MusicNowPlayingMetrics.lyricsHeaderSide)
        }
    }

    private var artworkThumb: some View {
        ZStack {
            TelegramTrackGradient.linear(track.messageId)
            if let image = artwork.image(for: track,
                                         side: MusicNowPlayingMetrics.lyricsHeaderSide) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: MusicNowPlayingMetrics.lyricsHeaderSide,
               height: MusicNowPlayingMetrics.lyricsHeaderSide)
        .clipShape(RoundedRectangle(cornerRadius: MusicNowPlayingMetrics.lyricsHeaderRadius,
                                    style: .continuous))
        .animation(MusicArtworkMetrics.loadFade, value: artwork.revision)
        .accessibilityElement()
        .accessibilityLabel(track.displayTitle)
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
    @State private var store = PlayerStore()

    var body: some View {
        AppleMusicLyricsView(
            lyrics: lyrics.lines,
            errorMessage: lyrics.errorMessage,
            highlightedLyricID: nil,
            isActive: true,
            isInterfaceHidden: false,
            // The transport row floats over this page rather than taking its own band, so the column
            // has to be told how much of its own bottom is not really its bottom: that is where the
            // fade stops and where the last line is allowed to rest.
            bottomOverlayHeight: MusicNowPlayingMetrics.overlayHeight,
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
