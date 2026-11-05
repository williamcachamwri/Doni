import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The hearts, in MeloX's favourite-songs shape: a plain `List`, a "play everything" row at its head,
/// the reference's song row, and a swipe that puts the heart back (`LibrarySongsView.swift:22-68`,
/// `TrackRowView.swift:17-59`). System chrome throughout — default insets, default separators.
/// A favourite is keyed by MTProto `unique_id`, so it survives a channel re-read or a deleted post; the
/// kept slice goes in the row's second line and the trailing column stays the song's length. Order is
/// newest heart first, not newest post.
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
                        description: Text("Nhấn giữ một bài trong Thư viện rồi chọn Yêu thích. Giữ cả bài, hoặc giữ lại đoạn bạn muốn nghe — đoạn đã giữ sẽ lặp lại khi phát.")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    /// The store's hearts under the library's toneless fold: "tinh yeu" finds "Tình yêu". Same rule as
    /// `LibraryIndexer.matches(of:)`, but the haystack is one row's three name fields.
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

    /// The kept range, or nil for a whole song. The dash is an en dash — a hyphen reads as subtraction.
    private func kept(of favorite: StoredFavorite) -> String? {
        guard let segment = favorite.segment,
              let from = MediaClock.duration(segment.lowerBound),
              let to = MediaClock.duration(segment.upperBound)
        else { return nil }
        return "\(from)–\(to)"
    }

    /// The count the bar has no room for: how many are kept, how many of those are a slice.
    private var countLine: Text {
        let kept = visible
        let slices = kept.filter { $0.segment != nil }.count
        guard slices > 0 else { return Text(localized("%@ bài", kept.count.formatted())) }
        return Text(localized("%@ bài · %@ đoạn", kept.count.formatted(), slices.formatted()))
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
