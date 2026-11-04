import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The hearts, in the shape MeloX gives its favourite songs: a plain `List`, a "play everything"
/// row at its head, one row per kept song, a swipe that puts the heart back
/// (`LibrarySongsView.swift:22-108`).
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
        List {
            if !visible.isEmpty {
                Button(action: playAll) {
                    HStack {
                        Label("Phát tất cả", systemImage: "play.fill")
                        Spacer()
                    }
                }
            }
            ForEach(visible) { favorite in
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
                    player.play(favorite.track, in: visible.map { $0.track as any Playable })
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        library.toggleFavorite(favorite.track)
                    } label: {
                        Label("Bỏ yêu thích", systemImage: "heart.slash")
                    }
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
            if !visible.isEmpty {
                countLine
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.chatListBackground.ignoresSafeArea())
        .navigationTitle("Yêu thích")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm trong Yêu thích")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: shuffleAll) {
                    Label("Phát ngẫu nhiên", systemImage: "shuffle").labelStyle(.iconOnly)
                }
                .disabled(visible.isEmpty)
            }
        }
        .refreshable { library.refresh() }
        .overlay {
            if visible.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(
                        "Chưa giữ bài nào",
                        systemImage: "heart",
                        description: Text("Nhấn giữ một bài trong Thư viện rồi chọn Yêu thích. "
                            + "Giữ cả bài, hoặc giữ lại đoạn bạn muốn nghe — đoạn đã giữ sẽ lặp lại "
                            + "khi phát.")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .animation(TelegramLoginMotion.easeInOut(0.2), value: visible.map(\.id))
    }

    /// The store's hearts, with the same toneless fold the library's search uses: "tinh yeu" finds
    /// "Tình yêu". Both sides are normalised, which is what `LibraryIndexer.matches(of:)` does for
    /// the whole library; here the haystack is one row's three name fields.
    private var visible: [StoredFavorite] {
        let key = SearchTextFold.normalized(query)
        guard !key.isEmpty else { return library.favorites }
        return library.favorites.filter {
            SearchTextFold.normalized(
                "\($0.track.displayTitle) \($0.track.displayPerformer) \($0.track.fileName)"
            ).contains(key)
        }
    }

    private func playAll() {
        guard let first = visible.first else { return }
        player.play(first.track, in: visible.map { $0.track as any Playable })
    }

    /// The shuffle the bar's trailing group runs, over the list currently on screen.
    private func shuffleAll() {
        var list = visible.map { $0.track as any Playable }
        guard !list.isEmpty else { return }
        list.shuffle()
        player.play(list[0], in: list)
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

    /// The count the bar no longer has room to carry: what is kept, and how much of it is a slice
    /// rather than a whole song.
    private var countLine: Text {
        let kept = visible
        let slices = kept.filter { $0.segment != nil }.count
        guard slices > 0 else { return Text("\(kept.count.formatted()) bài") }
        return Text("\(kept.count.formatted()) bài · \(slices.formatted()) đoạn")
    }
}

#Preview {
    NavigationStack {
        LikesView(
            session: TelegramSession(),
            player: Player(),
            artwork: CoverArtwork.shared,
            library: Library.shared
        )
    }
}
