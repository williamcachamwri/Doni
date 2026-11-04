import SwiftUI
import TelegramDesignSystem

/// MeloX's media card: the cover, then two lines of words under it, the card exactly as wide as
/// its own artwork (`MediaCardView.swift:11-28`, sized by `HomeRecommendationSections.swift:119-127`
/// and `HomeComponents.swift:99-114`).
///
/// The cover is a song's, whatever the card stands for: a playlist card wears the first song it
/// holds, which is the closest Doni gets to the artwork MeloX reads off the network.
struct HomeCard: View {
    let cover: any Playable
    let title: String
    let subtitle: String?
    /// The side the artwork is cut to, which is also the card's width — 154 for a song, 166 for a
    /// playlist (`MusicFeedMetrics.songCard`, `.playlistCard`).
    let side: CGFloat
    let artwork: CoverArtwork

    var body: some View {
        VStack(alignment: .leading, spacing: MusicFeedMetrics.cardTextGap) {
            TrackCover(track: cover, side: side,
                       radius: MusicArtworkMetrics.radius, artwork: artwork)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: side, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// One shelf of the feed: a title with a play-all circle on its baseline, and a strip of cards
/// under it that runs past both gutters (`HomeRecommendationSections.swift:79-113`).
struct HomeShelf<Content: View>: View {
    let title: String
    var playAll: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MusicFeedMetrics.headerToShelf) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.bold())
                Spacer()
                if let playAll {
                    Button(action: playAll) {
                        Label("Phát tất cả", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Phát tất cả \(title)")
                }
            }
            .padding(.horizontal, MusicFeedMetrics.gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: MusicFeedMetrics.shelfSpacing) {
                    content()
                }
            }
            .contentMargins(.horizontal, MusicFeedMetrics.gutter, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }
}
