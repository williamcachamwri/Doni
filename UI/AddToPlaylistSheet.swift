import SwiftUI
import Support
import TelegramDesignSystem

/// The sheet MeloX puts behind the ⋯ menu's "add to" button: an inline title, a "+" that makes a
/// new list, a cancel, and rows of a 52 pt cover at radius 7 beside the name with the song count
/// under it in `caption` secondary (`AddToPlaylistSheet.swift:13-121`, `:86-98`).
///
/// The reference's empty state offers a reload, because its lists live on a server that may simply
/// not have answered yet. A list that lives in Doni's own SQLite has nothing to reload, so the empty
/// state says the only true thing: make one — with the same button the toolbar holds.
struct AddToPlaylistSheet: View {
    let track: any Playable
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.dismiss) private var dismiss

    /// The naming sheet sits over this one, exactly as `PlaylistCreationSheet` sits over
    /// `AddToPlaylistSheet` in the reference (`AddToPlaylistSheet.swift:30-35`).
    @State private var showsCreation = false
    /// The first song each list wears, read once per row rather than on every redraw.
    @State private var covers: [Int64: StoreTrack] = [:]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Thêm vào danh sách")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Danh sách mới", systemImage: "plus") {
                            showsCreation = true
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Huỷ") { dismiss() }
                    }
                }
        }
        .sheet(isPresented: $showsCreation) {
            PlaylistNameSheet(title: "Danh sách mới", verb: "Tạo", initial: "") { text in
                create(text)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.playlists.isEmpty {
            ContentUnavailableView {
                Label("Chưa có danh sách nào", systemImage: "music.note.list")
            } description: {
                Text(localized("“%@” sẽ là bài đầu tiên của danh sách vừa tạo.", track.displayTitle))
            } actions: {
                Button("Danh sách mới") { showsCreation = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List(library.playlists) { list in
                Button {
                    library.add(track, to: list.id)
                    dismiss()
                } label: {
                    HStack(spacing: MusicPlaylistMetrics.addRowSpacing) {
                        PlaylistArt(listId: list.id, coverPath: list.coverPath,
                                    cover: covers[list.id],
                                    side: MusicPlaylistMetrics.addArt,
                                    radius: MusicPlaylistMetrics.addArtRadius,
                                    artwork: artwork)

                        VStack(alignment: .leading, spacing: MusicPlaylistMetrics.addTextGap) {
                            Text(list.name)
                                .lineLimit(1)
                            Text(list.trackCount == 0
                                ? "Chưa có bài nào"
                                : localized("%@ bài", list.trackCount.formatted()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .task(id: list.id) {
                    let cover = library.firstTrack(in: list.id)
                    covers[list.id] = cover
                    if let cover {
                        await artwork.load(track: cover, side: MusicPlaylistMetrics.addArt)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    /// A list made from here is not left empty for the user to fill afterwards: the song being
    /// listened to goes in, which also makes it the cover the list wears until one is chosen
    /// (`PlaylistArt`'s second tier). The picker stays open over the new row, the way the reference
    /// leaves it open over a list that has just been created.
    private func create(_ name: String) {
        guard let list = library.createPlaylist(named: name) else { return }
        library.add(track, to: list.id)
    }
}
