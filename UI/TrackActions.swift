import SwiftUI
import Support
import TelegramDesignSystem

/// The menu a song answers to wherever it was found: keep it, and put it in a list. Long press is the
/// reference's own gesture for a row (`ChatContextMenus.swift:83`); the verbs are Doni's. Playlists are
/// laid out flat rather than in a submenu — the one shape certain to render without a simulator run.
struct TrackActions<Additional: View>: ViewModifier {
    let track: any Playable
    @ObservedObject var library: Library
    /// What the screen holding the row wants on top of the two verbs every row has.
    @ViewBuilder var additional: () -> Additional

    /// The song whose new list is being named — held here because anything taking focus can dismiss
    /// the alert.
    @State private var naming: (any Playable)?
    @State private var name = ""

    func body(content: Content) -> some View {
        let kept = library.favorites.contains { $0.id == track.uniqueId }
        let lists = library.playlists
        return content
            .contextMenu {
                additional()
                Button {
                    library.toggleFavorite(track)
                } label: {
                    Label(kept ? "Bỏ yêu thích" : "Yêu thích",
                          systemImage: kept ? "heart.slash" : "heart")
                }
                Divider()
                ForEach(lists) { list in
                    Button(localized("Thêm vào “%@”", list.name)) {
                        library.add(track, to: list.id)
                    }
                }
                Button {
                    name = ""
                    naming = track
                } label: {
                    Label("Danh sách mới…", systemImage: "plus")
                }
            }
            .alert("Danh sách mới", isPresented: nameBeingEntered, presenting: naming) { target in
                TextField("Tên danh sách", text: $name)
                Button("Tạo") { create(target) }
                Button("Huỷ", role: .cancel) {}
            } message: { _ in
                Text(localized("“%@” sẽ nằm trong danh sách mới.", track.displayTitle))
            }
    }

    private var nameBeingEntered: Binding<Bool> {
        Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })
    }

    /// A blank name is refused by the store, so `nil` means there is no list: the song goes in only
    /// once the list really exists.
    private func create(_ target: any Playable) {
        guard let created = library.createPlaylist(named: name) else {
            naming = nil
            return
        }
        library.add(target, to: created.id)
        naming = nil
    }
}

extension View {
    func trackActions<Additional: View>(
        _ track: any Playable,
        library: Library,
        @ViewBuilder additional: @escaping () -> Additional = { EmptyView() }
    ) -> some View {
        modifier(TrackActions(track: track, library: library, additional: additional))
    }
}
