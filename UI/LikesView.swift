import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The hearts, in the shape MeloX gives its favourite songs: a plain `List`, a "play everything" row
/// at its head, the reference's own song row under it, and a swipe that puts the heart back
/// (`LibrarySongsView.swift:22-68`, `TrackRowView.swift:17-59`).
///
/// The chrome is the system's — default insets, default separators, no background of its own. What
/// this screen wore before was Telegram's chat list, which is a different app's screen: two tones of
/// surface, a hairline drawn by hand, and a play state in the row. The reference puts none of that in
/// front of a song list, so neither does this.
///
/// A favourite is keyed by MTProto's `unique_id` rather than by the post it came from, so a song stays
/// here after the channel is re-read or the message is deleted, and the one thing the store can keep
/// that a chat list cannot is the slice of it that was worth keeping. That goes in the row's second
/// line, which is the slot the reference reserves for one extra fact; the trailing column stays the
/// song's length. The order is the store's: newest heart first, not newest post.
struct LikesView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var query = ""

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
                Button {
                    player.play(favorite.track, in: visible.map { $0.track as any Playable })
                } label: {
                    MusicTrackRow(track: favorite.track, secondary: kept(of: favorite),
                                  artwork: artwork)
                        .task(id: favorite.track.uniqueId) {
                            await artwork.load(track: favorite.track, via: session.covers(),
                                               side: MusicSearchMetrics.songArt)
                        }
                }
                .buttonStyle(.plain)
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

    /// The range of the kept slice, or nothing at all for a whole song. The dash is an en dash,
    /// because a hyphen in a range reads as a subtraction.
    private func kept(of favorite: StoredFavorite) -> String? {
        guard let segment = favorite.segment,
              let from = MediaClock.duration(segment.lowerBound),
              let to = MediaClock.duration(segment.upperBound)
        else { return nil }
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
