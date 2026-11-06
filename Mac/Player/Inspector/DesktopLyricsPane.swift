import SwiftUI

/// The words in the desktop's panel and player page: the same column the phone draws, hosted rather
/// than reimplemented.
///
/// `AppleMusicLyricsView` is already cross-platform — `Packages/DoniLyrics` compiles for both targets,
/// and the column uses no UIKit — so the desktop gets the reference's scroll, focus cascade, per-line
/// glow and tap-to-seek by asking for the phone's driver. A second, simpler renderer here would have
/// been a second thing to keep true.
///
/// The only work this host adds is loading: the phone's Now Playing page is opened from a song that is
/// already being fetched, while the panel can be opened before anything has asked for its words.
struct DesktopLyricsPane: View {
    @EnvironmentObject private var lyrics: Lyrics
    @EnvironmentObject private var player: Player
    let isActive: Bool

    var body: some View {
        LyricsView(player: player, lyrics: lyrics, isActive: isActive)
            .task(id: player.current?.uniqueId) {
                guard let track = player.current else { return }
                lyrics.load(track)
            }
    }
}
