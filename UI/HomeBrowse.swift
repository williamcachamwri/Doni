import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The Home tab's two segments, which is how the reference splits the same screen
/// (`HomeView.swift:18-33`, `:36-47`): a `.segmented` picker over the section's own content.
///
/// MeloX's third segment is podcasts, and a Telegram music channel has no such thing, so the picker
/// has the two sections whose content this app actually holds.
enum DoniHomeSection: String, CaseIterable, Identifiable {
    case forYou
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: return "Dành cho bạn"
        case .music: return "Nhạc"
        }
    }
}

/// One chip and the songs it stands for.
struct HomeFacet: Identifiable {
    let title: String
    let tracks: [any Playable]

    var id: String { title }
}

/// The second segment, in the shape of the reference's discover screen (`ExploreView.swift:44-102`):
/// a row of capsule chips, the first thing the chosen chip leads with drawn as a full-width card, and
/// everything after it in a two-column grid.
///
/// The numbers are the reference's and are in `MusicExploreMetrics`. What differs is only where the
/// lists come from: MeloX asks Netease for a category's playlists, and Doni's categories are the four
/// groups its own store keeps plus the performers that appear most in it — the facets a channel
/// really has.
struct HomeBrowse: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    let facets: [HomeFacet]
    /// The door the empty screen opens, which is the Home tab's sheet rather than this segment's own.
    let addChannel: () -> Void
    let reload: () async -> Void

    @State private var selected: String

    init(session: TelegramSession, player: Player, artwork: CoverArtwork,
         facets: [HomeFacet], addChannel: @escaping () -> Void,
         reload: @escaping () async -> Void) {
        self.session = session
        self.player = player
        self.artwork = artwork
        self.facets = facets
        self.addChannel = addChannel
        self.reload = reload
        _selected = State(initialValue: facets.first?.title ?? "")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MusicExploreMetrics.sectionSpacing) {
                chips
                if let facet {
                    content(facet)
                }
            }
            .padding(.horizontal, MusicExploreMetrics.gutter)
            .padding(.bottom, MusicExploreMetrics.bottom)
        }
        .refreshable { await reload() }
    }

    private var facet: HomeFacet? {
        facets.first { $0.title == selected } ?? facets.first
    }

    /// `.borderedProminent` capsules, `.small`, the chosen one in the accent and the rest on grey at
    /// 0.14 (`ExplorePlaylistComponents.swift:10-20`).
    private var chips: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: MusicExploreMetrics.chipGap) {
                ForEach(facets) { entry in
                    Button(entry.title) {
                        selected = entry.title
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(entry.title == selected ? MusicTint.accent
                        : Color.secondary.opacity(MusicExploreMetrics.chipIdleInk))
                    .foregroundStyle(entry.title == selected ? Color.white : Color.primary)
                    .accessibilityAddTraits(entry.title == selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func content(_ facet: HomeFacet) -> some View {
        if facet.tracks.isEmpty {
            // One chip with nothing in it is a chip to leave; nothing anywhere is a library that has
            // never been pointed at a channel, and that has exactly one answer.
            if facets.allSatisfy({ $0.tracks.isEmpty }) {
                AddChannelPrompt("Thư viện đang trống", action: addChannel)
                    .padding(.top, 60)
            } else {
                ContentUnavailableView("Chưa có bài nào ở đây", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else {
            hero(facet)
            collection(facet)
        }
    }

    /// The first song of the chip, drawn as the reference's featured card: the cover at 1.55, a
    /// scrim that darkens toward the bottom, and the words laid over it
    /// (`ExplorePlaylistComponents.swift:44-81`).
    private func hero(_ facet: HomeFacet) -> some View {
        let track = facet.tracks[0]
        return Button {
            player.play(track, in: facet.tracks)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .aspectRatio(MusicExploreMetrics.heroAspect, contentMode: .fit)
                    .overlay { art(track) }
                    .clipShape(.rect(cornerRadius: MusicExploreMetrics.heroRadius))

                LinearGradient(colors: [Color.clear,
                                        Color.black.opacity(MusicExploreMetrics.heroScrim)],
                               startPoint: .center, endPoint: .bottom)
                    .clipShape(.rect(cornerRadius: MusicExploreMetrics.heroRadius))

                VStack(alignment: .leading, spacing: MusicExploreMetrics.heroTextGap) {
                    Text(facet.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(MusicExploreMetrics.heroBadgeInk))

                    Text(track.displayTitle)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: MusicExploreMetrics.heroMetaGap) {
                        Text(track.displayPerformer.trimmedSearchName.isEmpty
                            ? "Doni" : track.displayPerformer.trimmedSearchName)
                            .lineLimit(1)
                        if let text = MediaClock.duration(track.duration) {
                            Label(text, systemImage: "play.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(MusicExploreMetrics.heroMetaInk))
                }
                .padding(MusicExploreMetrics.heroPadding)
                .padding(.trailing, MusicExploreMetrics.heroPadding)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .task(id: track.uniqueId) {
            await artwork.load(track: track, via: session.covers(),
                               side: MusicExploreMetrics.cardAsk)
        }
    }

    /// The rest of the chip as a grid under a heading that counts it (`ExploreView.swift:90-104`).
    private func collection(_ facet: HomeFacet) -> some View {
        VStack(alignment: .leading, spacing: MusicExploreMetrics.headingGap) {
            HStack(alignment: .firstTextBaseline) {
                Text("Xem thêm")
                    .font(.title2.bold())
                Spacer()
                Text(localized("%@ bài", facet.tracks.count.formatted()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Self.columns, alignment: .leading,
                      spacing: MusicExploreMetrics.rowSpacing) {
                ForEach(facet.tracks.dropFirst(), id: \.uniqueId) { track in
                    Button {
                        player.play(track, in: facet.tracks)
                    } label: {
                        card(track)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func card(_ track: any Playable) -> some View {
        VStack(alignment: .leading, spacing: MusicExploreMetrics.cardTextGap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { art(track) }
                .clipShape(.rect(cornerRadius: MusicExploreMetrics.cardRadius))
                .overlay(alignment: .topTrailing) {
                    // The reference puts a play count here. Doni has no counts, so the pill carries
                    // the one number the post does have — how long the song is.
                    if let text = MediaClock.duration(track.duration) {
                        Label(text, systemImage: "play.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, MusicExploreMetrics.pillHorizontal)
                            .padding(.vertical, MusicExploreMetrics.pillVertical)
                            .background(.black.opacity(MusicExploreMetrics.pillInk), in: .capsule)
                            .padding(MusicExploreMetrics.pillMargin)
                    }
                }

            Text(track.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(track.displayPerformer.trimmedSearchName.isEmpty
                ? "Doni" : track.displayPerformer.trimmedSearchName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .task(id: track.uniqueId) {
            await artwork.load(track: track, via: session.covers(),
                               side: MusicExploreMetrics.cardAsk)
        }
    }

    /// The cover itself, filled into whatever box the card or the hero turned out to be.
    ///
    /// `scaledToFill` sizes the layout box, not only the pixels, so it is put in an `overlay` — the
    /// box is the `Color.clear`'s aspect ratio, and the picture that overflows it is clipped by the
    /// `clipShape` the caller applies.
    @ViewBuilder
    private func art(_ track: any Playable) -> some View {
        ZStack {
            TelegramTrackGradient.linear(track.messageId)
            if let image = artwork.image(for: track, side: MusicExploreMetrics.cardAsk) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .animation(MusicArtworkMetrics.loadFade, value: artwork.revision)
    }

    private static let columns = [
        GridItem(.adaptive(minimum: MusicExploreMetrics.columnMin,
                           maximum: MusicExploreMetrics.columnMax),
                 spacing: MusicExploreMetrics.columnSpacing)
    ]
}
