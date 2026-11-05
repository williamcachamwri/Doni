import SwiftUI
import TelegramDesignSystem

/// A song's artwork at the side the surface draws it, over Telegram's avatar gradient: one of seven
/// pairs picked by id, lighter stop on top (`PeerAvatar.swift:403-424`). The Library row has its own
/// tile because it also carries the download bubble.
/// The gradient doubles as the placeholder, unlike `ArtworkImage`'s grey plus `ProgressView`
/// (`ArtworkImage.swift:59-63`): twenty spinners are noisier than twenty colours. What is copied is the
/// arrival — `.transition(.opacity)` under `.easeOut(duration: 0.18)` (`:45-47`).
struct TrackCover: View {
    let track: any Playable
    let side: CGFloat
    let radius: CGFloat
    /// Read, not observed: the surface that owns the list observes the cache and re-renders this.
    let artwork: CoverArtwork

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MissingArtwork(side: side)
            if let image = artwork.image(for: track, side: side) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(reduceMotion ? nil : MusicArtworkMetrics.loadFade, value: artwork.revision)
    }
}
