import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The hearts: what the user kept, in the row the library wears.
///
/// A favourite is keyed by MTProto's `unique_id` rather than by the post it came from, so a song
/// stays here after the channel is re-read or the message is deleted, and the one thing the store
/// can keep that a chat list cannot is the slice of it that was worth keeping — which is why a row
/// here can read `1:20–4:05` where the library reads a duration. The order is the store's: newest
/// heart first, not newest post.
struct LikesView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.displayScale) private var displayScale
    @Environment(\.telegramFloatingClearance) private var floatingClearance

    private let palette = TelegramPalette.dark

    var body: some View {
        ZStack(alignment: .top) {
            rows
            GlassBar(
                title: "Yêu thích",
                actions: [
                    GlassBarAction(symbol: "shuffle", label: "Phát ngẫu nhiên") {
                        shuffleAll()
                    },
                ]
            )
        }
        .background(palette.chatListBackground.ignoresSafeArea())
    }

    /// The shuffle the bar's trailing group runs, over the whole kept list.
    private func shuffleAll() {
        var list = library.favorites.map { $0.track as any Playable }
        guard !list.isEmpty else { return }
        list.shuffle()
        player.play(list[0], in: list)
    }

    // MARK: List

    private var rows: some View {
        let kept = library.favorites
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(kept) { favorite in
                    TrackRow(
                        track: favorite.track,
                        query: "",
                        hairline: TelegramGeometry.hairline(displayScale: displayScale),
                        palette: palette,
                        isCurrent: player.current?.uniqueId == favorite.track.uniqueId,
                        isPlaying: player.current?.uniqueId == favorite.track.uniqueId
                            && player.isPlaying,
                        headline: headline(of: favorite),
                        isFavorite: true,
                        artwork: artwork
                    ) {
                        player.play(favorite.track, in: kept.map { $0.track as any Playable })
                    }
                    .trackActions(favorite.track, library: library) {
                        if let segment = favorite.segment {
                            Button("Chỉ phát đoạn đã lưu") {
                                player.play(
                                    segment: Double(segment.lowerBound)...Double(segment.upperBound),
                                    of: favorite.track
                                )
                            }
                        }
                    }
                    .task(id: favorite.track.uniqueId) {
                        await artwork.load(track: favorite.track, via: session.covers())
                    }
                }
                footer(kept)
            }
        }
        .contentMargins(.top, TelegramBarMetrics.topClearance, for: .scrollContent)
        .contentMargins(.bottom, floatingClearance, for: .scrollContent)
        .animation(TelegramLoginMotion.easeInOut(0.2), value: kept.map(\.id))
    }

    /// A marked slice is the more useful number on this screen: the whole song's length is already
    /// in the row's artwork tap. The dash is an en dash, because a hyphen in a range reads as a
    /// subtraction.
    private func headline(of favorite: StoredFavorite) -> String {
        guard let segment = favorite.segment,
              let from = MediaClock.duration(segment.lowerBound),
              let to = MediaClock.duration(segment.upperBound)
        else { return favorite.track.headline }
        return "\(from)–\(to)"
    }

    @ViewBuilder
    private func footer(_ kept: [StoredFavorite]) -> some View {
        if library.favorites.isEmpty {
            VStack(spacing: 12) {
                Text("Chưa giữ bài nào")
                    .font(TelegramLibraryTypography.barTitle)
                    .foregroundStyle(palette.chatListTitle)
                Text("Nhấn giữ một bài trong Thư viện rồi chọn Yêu thích. Giữ cả bài, hoặc giữ lại đoạn bạn muốn nghe — đoạn đã giữ sẽ lặp lại khi phát.")
                    .font(TelegramLibraryTypography.preview)
                    .foregroundStyle(palette.chatListMessageText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
            .padding(.top, 72)
        } else {
            // The count the bar no longer has room to carry: what is kept, and how much of it is
            // a slice rather than a whole song.
            Text(countLine(kept))
                .font(TelegramLibraryTypography.preview)
                .foregroundStyle(palette.chatListMessageText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    private func countLine(_ kept: [StoredFavorite]) -> String {
        let slices = kept.filter { $0.segment != nil }.count
        guard slices > 0 else { return "\(kept.count.formatted()) bài" }
        return "\(kept.count.formatted()) bài · \(slices.formatted()) đoạn"
    }
}

#Preview {
    LikesView(
        session: TelegramSession(),
        player: Player(),
        artwork: CoverArtwork.shared,
        library: Library.shared
    )
}
