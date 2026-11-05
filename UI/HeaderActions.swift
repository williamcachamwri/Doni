import SwiftUI
import TelegramDesignSystem

/// The header's verbs, drawn in the content instead of in the system's top bar.
///
/// A large-title bar puts its trailing items in the status row, and that row belongs to the Dynamic
/// Island the moment audio starts playing: the island grows over the app's own buttons, which is
/// exactly the state a listener is in. Nothing about the buttons changed — they are the same glass
/// discs the reference wears, in a glass container so they share one refraction — only the row they
/// live in moved, into the content under the title.
struct HeaderActionRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: MusicNowPlayingMetrics.actionDiscGap) {
            HStack(spacing: MusicNowPlayingMetrics.actionDiscGap) {
                Spacer(minLength: 0)
                content
            }
        }
        .padding(.horizontal, MusicExploreMetrics.gutter)
        .padding(.bottom, MusicExploreMetrics.gutter / 2)
    }
}
