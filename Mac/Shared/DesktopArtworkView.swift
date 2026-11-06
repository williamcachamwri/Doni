import Support
import SwiftUI
import TelegramDesignSystem

/// A cover the way the desktop draws one: the cached bitmap Doni already has, a placeholder when there
/// is none, and a clip rather than a shape — the reference's `DesktopArtworkView` is the same three
/// layers, but it fetches over the network with `AsyncImage` and Doni never does.
///
/// `CoverArtwork` publishes a revision every time a picture lands, which is what makes this view
/// correct without any loading state of its own: the row redraws when the bytes arrive, not when the
/// track changes.
struct DesktopArtworkView: View {
    @EnvironmentObject private var artwork: CoverArtwork
    let track: any Playable
    var side: CGFloat = 36
    var cornerRadius: CGFloat = MusicArtworkMetrics.radius

    var body: some View {
        ZStack {
            Color.secondary.opacity(MusicArtworkMetrics.placeholderFill)

            if let image = artwork.image(for: track, side: side) {
                Image(doni: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.36, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
