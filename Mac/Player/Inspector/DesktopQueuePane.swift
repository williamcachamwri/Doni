import SwiftUI
import TelegramDesignSystem

/// The up-next list, at the reference's inspector measurements (`DesktopQueueMetrics.swift:52-71`):
/// 16-point insets, a 44-point header, a 34-point cover, a 14pt medium title over a 12pt secondary
/// line, and a 72-point fade at the bottom so the last row dissolves instead of being cut.
///
/// Two things the reference has here, this app does not: an autoplay/automix row above the list (Doni
/// has no autoplay and no crossfade) and a history section (its queue keeps only what is still to
/// come). The measurements that are shared are taken exactly; the rows that do not exist are not
/// faked.
struct DesktopQueuePane: View {
    @EnvironmentObject private var player: Player

    private static let headerHeight: CGFloat = 44
    private static let rowLeadingInset: CGFloat = 16
    private static let rowTrailingInset: CGFloat = 10
    private static let rowVerticalInset: CGFloat = 7
    private static let bottomFadeHeight: CGFloat = 72

    private var upcoming: [(offset: Int, track: any Playable)] {
        player.upcomingIndices.map { ($0, player.queue[$0]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
    }

    private var header: some View {
        HStack {
            Text("Tiếp theo")
                .font(.system(size: 15, weight: .bold))
            Spacer()
            Button("Xoá") {
                player.remove(at: IndexSet(upcoming.map(\.offset)))
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MusicTint.accent)
            .disabled(upcoming.isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.headerHeight)
        .textCase(nil)
    }

    private var list: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if upcoming.isEmpty {
                        Text("Hàng đợi đã hết.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity,
                                   minHeight: max(geometry.size.height - Self.headerHeight, 55))
                    } else {
                        ForEach(upcoming, id: \.track.uniqueId) { entry in
                            DesktopQueueRow(track: entry.track, offset: entry.offset)
                                .padding(.vertical, Self.rowVerticalInset)
                                .padding(.leading, Self.rowLeadingInset)
                                .padding(.trailing, Self.rowTrailingInset)

                            if entry.offset != upcoming.last?.offset {
                                Divider()
                                    .overlay(Color.primary.opacity(0.10))
                                    .padding(.leading, Self.rowLeadingInset)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.bottomFadeHeight)
                }
            }
        }
    }
}

/// One row of it. The whole row is the play button — the reference makes the same choice — and the
/// ellipsis carries the only two verbs a queued song answers to: play it now, take it out.
struct DesktopQueueRow: View {
    @EnvironmentObject private var player: Player
    let track: any Playable
    let offset: Int

    var body: some View {
        HStack(spacing: 8) {
            Button {
                player.play(at: offset)
            } label: {
                HStack(spacing: 11) {
                    DesktopArtworkView(track: track, side: 34, cornerRadius: 5)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.displayTitle)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Text(track.displayPerformer)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Menu {
                Button("Phát", systemImage: "play.fill") { player.play(at: offset) }
                Button("Xoá khỏi hàng đợi", systemImage: "minus.circle", role: .destructive) {
                    player.remove(at: IndexSet(integer: offset))
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .tint(.primary)
        }
    }
}
