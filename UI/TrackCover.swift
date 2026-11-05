import SwiftUI
import TelegramDesignSystem

/// A song's artwork at whatever side the surface draws it, with Telegram's avatar gradient
/// underneath.
///
/// A track with no cover still gets colour, and it gets it the way a peer with no avatar does: one
/// of seven gradient pairs picked by id (`PeerAvatar.swift:403-424`), drawn vertically with the
/// lighter stop on top. The Library row uses its own tile because that one also carries the
/// download bubble; this is the plain version the player surfaces need.
///
/// The gradient is also the placeholder, which is where this diverges from the reference on purpose:
/// `ArtworkImage` shows `Color.secondary.opacity(0.12)` with a `ProgressView` inside until the bytes
/// arrive (`ArtworkImage.swift:59-63`), and twenty spinners is a noisier screen than twenty colours.
/// What is transcribed is how the cover comes in — `.transition(.opacity)` carried by
/// `.easeOut(duration: 0.18)` (`:45-47`), the animation the loader hands its own transaction — because
/// that is what makes a screen filling with artwork read as one motion instead of twenty pops.
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
