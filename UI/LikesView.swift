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

    @State private var query = ""

    private let palette = TelegramPalette.dark

    var body: some View {
        VStack(spacing: 0) {
            header
            rows
        }
        .background(palette.chatListBackground.ignoresSafeArea())
        .playerStrip(player: player, artwork: artwork, library: library)
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("Yêu thích")
                    .font(TelegramLibraryTypography.barTitle)
                    .foregroundStyle(palette.navPrimaryText)
                Text(subtitle)
                    .font(TelegramLibraryTypography.barSubtitle)
                    .foregroundStyle(palette.navSecondaryText)
                    .lineLimit(1)
            }
            .frame(height: TelegramLibraryMetrics.navigationBarHeight)
            SearchField(query: $query, placeholder: "Tìm trong bài đã thích")
        }
        .background(palette.navOpaqueBackground.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.navSeparator)
                .frame(height: TelegramGeometry.hairline(displayScale: displayScale))
        }
    }

    /// A count, in the same place the library shows the channel's name — the bar's second line is
    /// `regular(13)` wherever it says anything (`ChatTitleView.swift:27`).
    private var subtitle: String {
        let count = library.favorites.count
        let slices = library.favorites.filter { $0.segment != nil }.count
        guard count > 0 else { return "Chưa có bài nào" }
        guard slices > 0 else { return "\(count.formatted()) bài" }
        return "\(count.formatted()) bài · \(slices.formatted()) đoạn"
    }

    // MARK: List

    private var rows: some View {
        let kept = visible
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(kept) { favorite in
                    TrackRow(
                        track: favorite.track,
                        query: query,
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
        .scrollDismissesKeyboard(.interactively)
        .animation(TelegramLoginMotion.easeInOut(0.2), value: kept.map(\.id))
    }

    /// The same fold the library searches with, so a toneless query finds "Tình yêu" here too.
    private var visible: [StoredFavorite] {
        let needle = SearchTextFold.normalized(query)
        guard !needle.isEmpty else { return library.favorites }
        return library.favorites.filter { kept in
            let track = kept.track
            let haystack = SearchTextFold.normalized(
                "\(track.displayTitle) \(track.displayPerformer) \(track.fileName)"
            )
            return haystack.contains(needle)
        }
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
        } else if kept.isEmpty {
            Text("Không tìm thấy “\(query)”")
                .font(TelegramLibraryTypography.preview)
                .foregroundStyle(palette.chatListMessageText)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
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
