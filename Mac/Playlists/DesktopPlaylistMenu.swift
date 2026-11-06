import SwiftUI
import Support
import TelegramDesignSystem

/// The playlist half of a song's ⋯ menu, in the reference's shape: one submenu named for the verb, the
/// "make a list" row at its top and every list the listener owns under it
/// (`Shared/DesktopTrackRow.swift:151-170`).
///
/// Making a list is offered whether or not there are any, because the two questions are unrelated —
/// a listener with eleven lists may still want a twelfth, and the reference's own row does not hide the
/// create button behind an empty library.
struct DesktopPlaylistMenu: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    let track: any Playable

    var body: some View {
        Menu {
            Button("Danh sách mới…", systemImage: "plus") {
                model.ui.playlistTarget = DesktopPlaylistTarget(track: track)
            }

            if !library.playlists.isEmpty {
                Divider()
                ForEach(library.playlists) { list in
                    Button(localized("Thêm vào “%@”", list.name)) {
                        library.add(track, to: list.id)
                    }
                }
            }
        } label: {
            Label("Thêm vào danh sách", systemImage: "music.note.list")
        }
    }
}

/// The naming card the shell opens for that button. One field, one verb, and the song goes into the
/// list the moment it exists — the phone's rule, kept: a blank name is refused by the store, so nothing
/// is half-added.
struct DesktopNewPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: Library
    let track: any Playable
    @State private var name = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("Danh sách mới")
                .font(.system(size: 15, weight: .semibold))

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Tên danh sách", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit(create)

            HStack {
                Button("Huỷ") { dismiss() }
                Button("Tạo", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    /// Which song is on its way in, so the field is not being filled blind.
    private var title: String {
        localized("“%@” sẽ là bài đầu tiên của danh sách vừa tạo.", track.displayTitle)
    }

    private func create() {
        guard let created = library.createPlaylist(named: name) else { return }
        library.add(track, to: created.id)
        dismiss()
    }
}
