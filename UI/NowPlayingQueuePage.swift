import Support
import SwiftUI
import TelegramDesignSystem
import TdSession

/// The up-next page, transcribed from MeloX's `NowPlayingQueuePage.swift`: a plain `List` whose first
/// row is reserved space — the pinned header's height plus the 60 pt pill band (`:44-49`) — with the
/// header and pills as two overlays slid back by the scroll offset (`:100-126`), so the header stays
/// put without the list resizing and a mask, not a fade, hides the rows gone past it (`:96-99`).
/// Edit mode is pinned on so the tail reorders by drag (`:95`); there is no swipe-to-delete.
struct NowPlayingQueuePage: View {
    /// The song under the header, which is the one the pills act on.
    let track: any Playable
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the list has taken the header up, clamped to the header's own height so it stops at
    /// the top rather than sliding out of the mask.
    @State private var scrollOffset: CGFloat = 0

    private let headerHeight = MusicNowPlayingMetrics.songHeaderHeight

    var body: some View {
        List {
            Color.clear
                .frame(height: headerHeight + MusicQueueMetrics.headerReserveExtra)
                .listRowInsets(.init())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityHidden(true)

            Section {
                Text("Tiếp theo")
                    .font(MusicQueueMetrics.headingFont)
                    .foregroundStyle(.white)
                    .padding(.top, MusicQueueMetrics.headingTop)
                    .padding(.bottom, MusicQueueMetrics.headingBottom)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if upcoming.isEmpty {
                        ContentUnavailableView("Hết hàng chờ", systemImage: "list.bullet")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .listRowInsets(.init(top: MusicQueueMetrics.emptyRowInset, leading: 0,
                                                 bottom: MusicQueueMetrics.emptyRowInset,
                                                 trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(rows) { row in
                            QueueRowView(row: row, player: player, artwork: artwork,
                                         covers: session.covers())
                        }
                        .onMove(perform: move)
                    }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.visible)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.top, visibleTop, for: .scrollIndicators)
        .environment(\.defaultMinListRowHeight, 1)
        .environment(\.defaultMinListHeaderHeight, 0)
        .environment(\.editMode, .constant(.active))
        .mask {
            Rectangle()
                .padding(.top, visibleTop)
        }
        .overlay(alignment: .top) {
            ModePills(player: player)
                .padding(.vertical, MusicQueueMetrics.pillRowPadding)
                .frame(height: MusicQueueMetrics.pillRowHeight)
                .offset(y: pillsOffset)
        }
        .overlay(alignment: .top) {
            QueueSongHeader(track: track, player: player, artwork: artwork, library: library)
                .offset(y: -scrollOffset)
                .clipped()
        }
        .padding(.bottom, MusicNowPlayingMetrics.coreHeight)
        .onScrollGeometryChange(for: CGFloat.self) { edge in
            min(max(edge.contentOffset.y + edge.contentInsets.top, 0), headerHeight)
        } action: { _, offset in
            scrollOffset = offset
        }
    }

    /// The queue's tail — MeloX's `unplayedQueueIndices` (`PlayerStore.swift:89`), which is
    /// `upcomingIndices(wraps: false)` (`PlaybackQueue.swift:66-78`).
    private var upcoming: [Int] {
        player.upcomingIndices
    }

    private var rows: [QueuedRow] {
        upcoming.map { position in
            QueuedRow(position: position, track: player.queue[position])
        }
    }

    /// The pills sit directly under the header while it is still on screen, and stop at the top
    /// once it has gone (`:181-183`).
    private var pillsOffset: CGFloat {
        max(headerHeight - scrollOffset, 0)
    }

    private var visibleTop: CGFloat {
        pillsOffset + MusicQueueMetrics.pillRowHeight
    }

    /// A drag on this page moves rows of the tail, so the offsets are lifted onto the whole queue
    /// inside the player (`:212-222`).
    private func move(from offsets: IndexSet, to destination: Int) {
        withAnimation(reduceMotion ? nil : MusicQueueMetrics.reorder) {
            player.moveUpcoming(from: offsets, to: destination)
        }
    }
}

/// One row of the tail: its position in the whole queue, which is what a tap and a drag both need.
private struct QueuedRow: Identifiable {
    let position: Int
    let track: any Playable

    var id: String { track.uniqueId }
}

/// The row at the size the reference gives it: 48 pt cover at radius 6, the name in `.body` over
/// the artist in `.subheadline` at white 0.58, 2 pt apart, 4 pt of row inset
/// (`NowPlayingQueuePage.swift:331-378`).
private struct QueueRowView: View {
    let row: QueuedRow
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    let covers: TdFileDownloader?

    var body: some View {
        Button(action: play) {
            HStack(spacing: MusicQueueMetrics.rowGap) {
                TrackCover(track: row.track, side: MusicQueueMetrics.rowArt,
                           radius: MusicQueueMetrics.rowArtRadius, artwork: artwork)
                VStack(alignment: .leading, spacing: MusicQueueMetrics.rowTextGap) {
                    Text(row.track.displayTitle)
                        .font(.body)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(row.track.displayPerformer.isEmpty ? "Doni" : row.track.displayPerformer)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(MusicQueueMetrics.rowArtistOpacity))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(.init(top: MusicQueueMetrics.rowInset, leading: 0,
                             bottom: MusicQueueMetrics.rowInset, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .task(id: row.track.uniqueId) {
            await artwork.load(track: row.track, via: covers,
                               side: MusicQueueMetrics.rowArt)
        }
    }

    private func play() {
        player.play(at: row.position)
    }
}

/// The header the queue scrolls under: the playing song at the reference's pinned size
/// (`NowPlayingSongHeader.swift:65-97`). MeloX's `usesReferenceLayout` is the variant that drops the
/// star and keeps only the ⋯ disc (`:117-119`, `NowPlayingSongActions.swift:16`).
///
/// The artwork slot is empty on purpose: the panel draws the cover itself
/// (`NowPlayingView.swift:233-255`), which is what lets the same picture be the hero on the artwork
/// page and this thumb on the queue. Without this, the header's own `TrackCover` would scroll with
/// the list while the panel's cover stayed fixed — two covers, one of them disappearing.
private struct QueueSongHeader: View {
    let track: any Playable
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    var body: some View {
        HStack(spacing: MusicNowPlayingMetrics.songHeaderGap) {
            Color.clear
                .frame(width: MusicNowPlayingMetrics.lyricsHeaderSide,
                       height: MusicNowPlayingMetrics.lyricsHeaderSide)
            VStack(alignment: .leading, spacing: MusicNowPlayingMetrics.titleSpacing) {
                Text(track.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(track.displayPerformer.isEmpty ? "Doni" : track.displayPerformer)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(MusicNowPlayingMetrics.artistOpacity))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SongActions(track: track, player: player, artwork: artwork, library: library)
        }
        .frame(height: MusicNowPlayingMetrics.songHeaderHeight)
    }
}

/// The three mode pills, in the chrome MeloX gives all four of its own
/// (`NowPlayingQueuePage.swift:225-329`). Autoplay and AutoMix are Netease features a Telegram channel
/// has no use for, so Doni's third slot is the cut.
private struct ModePills: View {
    @ObservedObject var player: Player

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: MusicQueueMetrics.pillGap) {
            pill(system: "shuffle", on: player.isShuffled,
                 label: player.isShuffled ? "Tắt phát ngẫu nhiên" : "Phát ngẫu nhiên") {
                player.setShuffled(!player.isShuffled)
            }
            pill(system: player.repeatSystemImage, on: player.repeatMode != .off,
                 label: repeatLabel) {
                player.cycleRepeatMode()
            }
            pill(system: "scissors", on: player.segment != nil || player.markIn != nil,
                 label: cutLabel, action: cut)
        }
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "Lặp lại toàn bộ"
        case .all: return "Lặp lại một bài"
        case .one: return "Tắt lặp lại"
        }
    }

    private var cutLabel: String {
        if player.segment != nil { return "Bỏ cắt đoạn" }
        if player.markIn != nil { return "Kết thúc cắt tại đây" }
        return "Bắt đầu cắt tại đây"
    }

    /// Mark, play on, mark again — the pill is the whole three-step flow in one control, because
    /// the time it needs is the one already running under the scrubber.
    private func cut() {
        if player.segment != nil {
            player.clearCut()
        } else if player.markIn != nil {
            player.markEnd()
        } else {
            player.markStart()
        }
    }

    private func pill(system: String, on: Bool, label: String,
                      action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : MusicQueueMetrics.pillToggle) {
                action()
            }
        } label: {
            Image(systemName: system)
                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol))
                .font(MusicQueueMetrics.pillGlyph)
                .frame(maxWidth: .infinity)
                .frame(height: MusicQueueMetrics.pillHeight)
                .foregroundStyle(on ? .black.opacity(MusicQueueMetrics.pillOnInk)
                                    : .white.opacity(MusicQueueMetrics.pillIdleInk))
                .background(Color.white.opacity(on ? MusicQueueMetrics.pillOnFill
                                                    : MusicQueueMetrics.pillIdleFill),
                            in: .rect(cornerRadius: MusicQueueMetrics.pillRadius))
                .contentShape(.rect(cornerRadius: MusicQueueMetrics.pillRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizedStringKey(label))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
