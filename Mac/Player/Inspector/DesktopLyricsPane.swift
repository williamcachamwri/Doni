import DoniLyrics
import DoniLyricsDesktop
import SwiftUI
import TelegramDesignSystem

/// The words, drawn by the reference's own desktop column.
///
/// `MeloXDesktop` renders lyrics with a stack of its own — `DesktopLyricsScrollView` and
/// `DesktopLyricLineView` — which is where its distance blur, hover-to-clear and per-line focus
/// cascade come from. Doni used to show the phone's renderer here instead, with the blur radius
/// pinned to zero under `#if os(macOS)`; that is why the desktop words looked flat and the blur
/// setting did nothing.
///
/// The two forms are the reference's split, not a new one: the inspector column asks for
/// `compact: true, allowsLyricBlur: false` (`DesktopPlayerInspector.swift:11-18`) because a 258 pt
/// column reads per-glyph blur as a defect, and the full-window player asks for `compact: false`
/// with blur left on.
///
/// What is *not* here is a second lyric pipeline. The reference's `LyricsStore` fetches through
/// `LyricsService`; Doni already fetches through its own providers, so only the four facts the
/// column reads — `lyrics`, `songID`, `isLoading`, `errorMessage` — are mirrored out of
/// `Lyrics.shared`, and the four the player reads are mirrored out of `Player`.
struct DesktopLyricsPane: View {
    @EnvironmentObject private var lyrics: Lyrics
    @EnvironmentObject private var player: Player
    let isActive: Bool
    /// `false` in the inspector, `true` in the player, matching the reference's two call sites.
    var compact = true
    var allowsLyricBlur = true
    /// The outer top inset the column has to see through to keep the sung line in Music's focus
    /// band. The full-window player pays it because its panel starts at `chromeHeight + 88`.
    var focusLift: CGFloat = 0

    @State private var store: PlayerStore
    @State private var words: DesktopLyricsModel

    init(isActive: Bool,
         compact: Bool = true,
         allowsLyricBlur: Bool = true,
         focusLift: CGFloat = 0) {
        self.isActive = isActive
        self.compact = compact
        self.allowsLyricBlur = allowsLyricBlur
        self.focusLift = focusLift
        _store = State(initialValue: PlayerStore())
        _words = State(initialValue: DesktopLyricsModel())
    }

    var body: some View {
        DesktopLyricsColumn(compact: compact,
                            allowsLyricBlur: allowsLyricBlur,
                            isActive: isActive,
                            focusLift: focusLift,
                            player: store,
                            lyrics: words,
                            settings: Lyrics.settings)
            .onAppear(perform: publish)
            // The column answers progress from the last position it was told plus the time since,
            // so the write is the reference's own clock rather than a per-frame push.
            .onChange(of: player.elapsed) { _, seconds in store.progress = seconds }
            .onChange(of: player.isPlaying) { _, playing in
                store.isPlaying = playing
                store.rate = playing ? 1 : 0
            }
            .onChange(of: player.current?.uniqueId) { _, _ in publish() }
            .onChange(of: lyrics.lines.count) { _, _ in publish() }
            .task(id: player.current?.uniqueId) {
                guard let track = player.current else { return }
                lyrics.load(track)
            }
    }

    /// Hand the column the song it is looking at, and the way back to the player when a line is
    /// tapped. The seek holds the store weakly on purpose: the store owns the closure, so a strong
    /// `self` is a cycle the pane would never break.
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
        words.lyrics = lyrics.lines
        words.isLoading = lyrics.isLoading
        words.errorMessage = lyrics.errorMessage
        words.songID = player.current?.uniqueId
    }
}
