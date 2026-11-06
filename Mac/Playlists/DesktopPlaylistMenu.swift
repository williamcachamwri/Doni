import SwiftUI
import Support
import TelegramDesignSystem

/// The playlist half of a song's ⋯ menu: the "make a list" row and every list the listener owns under
/// it (`Shared/DesktopTrackRow.swift:151-170`).
///
/// Flat items, not the reference's submenu, and that is the one place this port refuses to copy: a
/// `Menu` nested inside a `Menu` makes the outer one open and close again on macOS 26, so the ⋯
/// flickers and nothing in it can be clicked.
///
/// Making a list is offered whether or not any exist, because the two questions are unrelated — a
/// listener with eleven lists may still want a twelfth.
struct DesktopPlaylistMenuItems: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var library: Library
    let track: any Playable

    var body: some View {
        Button("Danh sách mới…", systemImage: "plus") {
            model.ui.playlistTarget = DesktopPlaylistTarget(track: track)
        }

        ForEach(library.playlists) { list in
            Button(localized("Thêm vào “%@”", list.name)) {
                library.add(track, to: list.id)
            }
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
