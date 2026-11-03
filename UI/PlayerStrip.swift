import SwiftUI
import TelegramDesignSystem

/// The strip of player a tab sits above, and the full-screen player tapping it opens.
///
/// Every list in the shell ends the same way: the list scrolls, the strip holds the bottom edge,
/// and the strip is closed unless the user is in the middle of something. Hosting it once in the
/// shell would be the tidier place, but a tab is written before the shell exists, so it lives
/// behind one modifier call per tab instead — and the hoist is then a deletion, not a rewrite.
struct PlayerStripHost: ViewModifier {
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork

    /// The strip is the closed state of the player; opening it is the strip's only job.
    @State private var showsPlayer = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayerBar(player: player, artwork: artwork) { showsPlayer = true }
                    .transition(.offset(y: TelegramShellMetrics.miniPlayerHeight)
                        .combined(with: .opacity))
            }
            .fullScreenCover(isPresented: $showsPlayer) {
                NowPlayingView(player: player, artwork: artwork)
            }
            .animation(TelegramShellMotion.appear, value: player.current?.uniqueId)
    }
}

extension View {
    func playerStrip(player: Player, artwork: CoverArtwork) -> some View {
        modifier(PlayerStripHost(player: player, artwork: artwork))
    }
}
