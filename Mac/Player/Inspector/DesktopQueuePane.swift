import SwiftUI
import TelegramDesignSystem

/// Where the up-next list is being shown, which decides its insets, its separators and how much room it
/// leaves for whatever floats over it (`DesktopQueueMetrics.swift:3-7`).
enum DesktopQueuePresentation: Hashable {
    case inspector
    case nowPlaying
}

/// The reference's two measurement sets (`DesktopQueueMetrics.swift:30-92`), kept whole for the
/// presentations that exist. The mini player's is not here because the mini player is not here.
struct DesktopQueueMetrics {
    let modeHorizontalPadding: CGFloat
    let modeSpacing: CGFloat
    let modeTopPadding: CGFloat
    let modeHeight: CGFloat
    let headerHorizontalPadding: CGFloat
    let headerHeight: CGFloat
    let rowLeadingInset: CGFloat
    let rowTrailingInset: CGFloat
    let artworkSize: CGFloat
    let rowOuterSpacing: CGFloat
    let rowContentSpacing: CGFloat
    let rowVerticalInset: CGFloat
    let rowTitleFont: Font
    let rowSubtitleFont: Font
    let menuSize: CGFloat
    let clearFont: Font
    let bottomFadeHeight: CGFloat
    let bottomInset: CGFloat

    init(presentation: DesktopQueuePresentation) {
        switch presentation {
        case .nowPlaying:
            modeHorizontalPadding = 9
            modeSpacing = 11
            modeTopPadding = 38
            modeHeight = 38
            headerHorizontalPadding = 15
            headerHeight = 44
            rowLeadingInset = 15
            rowTrailingInset = 9
            artworkSize = 34
            rowOuterSpacing = 8
            rowContentSpacing = 11
            rowVerticalInset = 7
            rowTitleFont = .system(size: 14, weight: .medium)
            rowSubtitleFont = .system(size: 12, weight: .regular)
            menuSize = 28
            clearFont = .system(size: 14, weight: .medium)
            bottomFadeHeight = 72
            bottomInset = 64
        case .inspector:
            modeHorizontalPadding = 9
            modeSpacing = 9
            modeTopPadding = 7
            modeHeight = 38
            headerHorizontalPadding = 16
            headerHeight = 44
            rowLeadingInset = 16
            rowTrailingInset = 10
            artworkSize = 34
            rowOuterSpacing = 8
            rowContentSpacing = 11
            rowVerticalInset = 7
            rowTitleFont = .system(size: 14, weight: .medium)
            rowSubtitleFont = .system(size: 12, weight: .regular)
            menuSize = 28
            clearFont = .system(size: 14, weight: .medium)
            bottomFadeHeight = 72
            bottomInset = 0
        }
    }
}

/// The up-next list (`DesktopQueueView.swift`).
///
/// The reference's mode row is autoplay and automix — a service that keeps offering songs and a
/// crossfader between them. Doni has neither, and the two modes it does have are shuffle and repeat, so
/// those are what wear the capsules. Same slot, same measurements, honest contents.
struct DesktopQueuePane: View {
    @EnvironmentObject private var player: Player
    var presentation: DesktopQueuePresentation = .inspector

    private var metrics: DesktopQueueMetrics {
        DesktopQueueMetrics(presentation: presentation)
    }

    private var upcoming: [(offset: Int, track: any Playable)] {
        player.upcomingIndices.map { ($0, player.queue[$0]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            modeRow
                .padding(.horizontal, metrics.modeHorizontalPadding)
                .padding(.top, metrics.modeTopPadding)

            list
                .padding(.bottom, metrics.bottomInset)
        }
    }

    private var modeRow: some View {
        HStack(spacing: metrics.modeSpacing) {
            modeButton("Phát ngẫu nhiên", systemImage: "shuffle",
                       isSelected: player.isShuffled) {
                player.setShuffled(!player.isShuffled)
            }
            modeButton(player.repeatMode == .one ? "Lặp lại một bài" : "Lặp lại toàn bộ",
                       systemImage: player.repeatSystemImage,
                       isSelected: player.repeatMode != .off) {
                player.cycleRepeatMode()
            }
        }
    }

    private func modeButton(_ title: String, systemImage: String, isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.88))
                .frame(maxWidth: .infinity)
                .frame(height: metrics.modeHeight)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .background(isSelected ? MusicTint.accent : Color.primary.opacity(0.10), in: .capsule)
        .overlay {
            Capsule().stroke(.primary.opacity(0.07), lineWidth: 0.5)
        }
        .accessibilityLabel(Text(localized(title)))
        .accessibilityValue(Text(localized(isSelected ? "Đang chọn" : "Chưa chọn")))
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    private var list: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 0) {
                    header

                    if upcoming.isEmpty {
                        Text("Hàng đợi đã hết.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity,
                                   minHeight: max(geometry.size.height - metrics.headerHeight, 55))
                    } else {
                        rows
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: metrics.bottomFadeHeight)
                }
            }
        }
    }

    /// The reference's header names the list and where it came from, then offers the one destructive
    /// verb in the app's red (`DesktopQueueView.swift:140-160`).
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Tiếp theo")
                    .font(.system(size: 15, weight: .bold))
                if let performer = player.current?.displayPerformer, !performer.isEmpty {
                    Text(localized("Từ: %@", performer))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("Xoá") {
                player.remove(at: IndexSet(upcoming.map(\.offset)))
            }
            .buttonStyle(.plain)
            .font(metrics.clearFont)
            .foregroundStyle(MusicTint.accent)
            .disabled(upcoming.isEmpty)
        }
        .padding(.horizontal, metrics.headerHorizontalPadding)
        .frame(height: metrics.headerHeight)
        .textCase(nil)
    }

    private var rows: some View {
        ForEach(upcoming, id: \.track.uniqueId) { entry in
            DesktopQueueRow(track: entry.track, offset: entry.offset, metrics: metrics)
                .padding(.vertical, metrics.rowVerticalInset)
                .padding(.leading, metrics.rowLeadingInset)
                .padding(.trailing, metrics.rowTrailingInset)

            if entry.offset != upcoming.last?.offset {
                Divider()
                    .overlay(separatorColor)
                    .padding(.leading, metrics.rowLeadingInset)
            }
        }
    }

    private var separatorColor: Color {
        presentation == .nowPlaying
            ? Color.white.opacity(0.13)
            : Color.primary.opacity(0.10)
    }
}

/// One row. The whole row is the play button, as in the reference, and the ellipsis carries the only
/// two verbs a queued song answers to.
struct DesktopQueueRow: View {
    @EnvironmentObject private var player: Player
    let track: any Playable
    let offset: Int
    let metrics: DesktopQueueMetrics

    var body: some View {
        HStack(spacing: metrics.rowOuterSpacing) {
            Button {
                player.play(at: offset)
            } label: {
                HStack(spacing: metrics.rowContentSpacing) {
                    DesktopArtworkView(track: track, side: metrics.artworkSize, cornerRadius: 5)
                        .frame(width: metrics.artworkSize, height: metrics.artworkSize)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.displayTitle)
                            .font(metrics.rowTitleFont)
                            .lineLimit(1)
                        Text(track.displayPerformer)
                            .font(metrics.rowSubtitleFont)
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
                    .frame(width: metrics.menuSize, height: metrics.menuSize)
                    .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .tint(.primary)
        }
    }
}
