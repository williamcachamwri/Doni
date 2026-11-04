import SwiftUI
import TelegramDesignSystem

/// A song's artwork at whatever side the surface draws it, with Telegram's avatar gradient
/// underneath.
///
/// A track with no cover still gets colour, and it gets it the way a peer with no avatar does: one
/// of seven gradient pairs picked by id (`PeerAvatar.swift:403-424`), drawn vertically with the
/// lighter stop on top. The Library row uses its own tile because that one also carries the
/// download bubble; this is the plain version the player surfaces need.
struct TrackCover: View {
    let track: any Playable
    let side: CGFloat
    let radius: CGFloat
    /// Read, not observed: the surface that owns the list observes the cache and re-renders this.
    let artwork: CoverArtwork

    var body: some View {
        ZStack {
            TelegramTrackGradient.linear(track.messageId)
            if let image = artwork.image(for: track, side: side) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
