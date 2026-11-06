import SwiftUI
import Support
import TelegramDesignSystem

/// A list of songs, laid out the way the reference lays a collection out
/// (`DesktopLibraryView.swift:26-41`): a 32pt bold title with its actions on the same baseline, then the
/// rows, inside a scroll view with 34 points of horizontal and 28 of vertical padding.
///
/// Every pane that shows songs — liked, recent, downloaded, cloud, search results, a playlist, a
/// channel — is this one view with a different array in it, which is also how the reference does it:
/// one `DesktopLibraryView` behind nine sections.
struct DesktopTrackPane: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var player: Player

    /// A sentence already resolved by the caller: the pane is handed a title that is sometimes a
    /// section's name and sometimes a playlist's or a search's, and only the caller knows which.
    let title: String
    let tracks: [any Playable]
    /// What the pane is for, when the answer to "why is this empty" is a door rather than a sentence.
    var emptyPrompt: String?
    var openDoor: (() -> Void)?
    var onRemove: ((any Playable) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    if !tracks.isEmpty { headerActions }
                }

                if tracks.isEmpty {
                    emptyState
                } else {
                    rows
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .navigationTitle(Text(title))
    }

    private var rows: some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(tracks.enumerated()), id: \.element.uniqueId) { offset, track in
                DesktopTrackRow(
                    track: track,
                    index: offset,
                    tracks: tracks,
                    showsArtwork: true,
                    onRemove: onRemove
                )
            }
        }
    }

    /// The reference puts its collection actions on the title's baseline: play the whole list, and play
    /// it in no particular order.
    private var headerActions: some View {
        HStack(spacing: 10) {
            Button {
                guard let first = tracks.first else { return }
                player.play(first, in: tracks)
            } label: {
                Label("Phát tất cả", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(MusicTint.accent)

            Button {
                guard let first = tracks.first else { return }
                player.setShuffled(true)
                player.play(first, in: tracks)
            } label: {
                Label("Phát ngẫu nhiên", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    @ViewBuilder private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyPrompt ?? title, systemImage: "music.note.list")
        } description: {
            Text(localized("Chưa có bài nào ở đây."))
        } actions: {
            if let openDoor {
                Button(action: openDoor) { Text("Thêm kênh") }
                    .buttonStyle(.borderedProminent)
                    .tint(MusicTint.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// The sections' queries over the library the walk has already filled.
///
/// They read `indexer.tracks` rather than `library.storedTracks` where the phone does the same: the
/// walk's list is what the listener is watching arrive, and a pane that waited for the store would lag
/// the very progress the sidebar is reporting.
@MainActor
enum DesktopPanes {
    /// Everything the account's channels have posted, newest first — the phone's "Nhạc" list.
    static func all(_ model: DesktopAppModel) -> [any Playable] {
        model.indexer.tracks
    }

    static func favorites(_ model: DesktopAppModel) -> [any Playable] {
        model.library.favorites.map(\.track)
    }

    static func recent(_ model: DesktopAppModel) -> [any Playable] {
        model.library.recentlyPlayed
    }

    static func downloaded(_ model: DesktopAppModel) -> [any Playable] {
        model.library.storedTracks.filter(\.isDownloaded)
    }

    static func cloud(_ model: DesktopAppModel) -> [any Playable] {
        model.cloud.songs
    }

    static func playlist(_ model: DesktopAppModel, id: Int64) -> [any Playable] {
        model.library.tracks(in: id)
    }

    static func channel(_ model: DesktopAppModel, chatId: Int64) -> [any Playable] {
        model.indexer.tracks.filter { $0.chatId == chatId }
    }

    static func search(_ model: DesktopAppModel, query: String) -> [any Playable] {
        model.indexer.matches(of: query)
    }
}
