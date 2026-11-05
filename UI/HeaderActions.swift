import SwiftUI
import TelegramDesignSystem

/// The header's verbs, drawn in the content instead of in the system's top bar.
///
/// A large-title bar puts its trailing items in the status row, and that row belongs to the Dynamic
/// Island the moment audio starts playing: the island grows, and the app's own buttons end up under
/// it — unreachable and unreadable, which is exactly what happened on the home tab while a song was
/// playing. Nothing about the circles changed; only the row they live in did.
struct HeaderActionRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: MusicNowPlayingMetrics.actionDiscGap) {
            Spacer(minLength: 0)
            content
        }
        .padding(.horizontal, MusicExploreMetrics.gutter)
        .padding(.bottom, MusicExploreMetrics.gutter / 2)
    }
}

/// The 40 pt glass disc the reference draws its header verbs in — the same disc the player's
/// ellipsis wears, so a header button and a panel button read as the same kind of thing
/// (`NowPlayingSongActions.swift:215-221`).
struct HeaderCircle<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: MusicNowPlayingMetrics.actionDisc,
                   height: MusicNowPlayingMetrics.actionDisc)
            .background(Color.white.opacity(MusicNowPlayingMetrics.menuDiscFill), in: .circle)
            .contentShape(.circle)
    }
}
