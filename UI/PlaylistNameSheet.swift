import SwiftUI
import TelegramDesignSystem

/// The sheet behind the "+" of both the playlist list and the add-to-playlist picker: a medium detent,
/// an inline title, a grouped form whose only field is the name (`PlaylistCreationSheet.swift:13-52`).
/// The reference's second row is a privacy toggle for a list it uploads to a server; Doni's list is
/// local SQLite, so there is nothing to keep private.
struct PlaylistNameSheet: View {
    let title: String
    let verb: String
    /// What the field starts with — empty for a new list, the old name for a rename.
    let initial: String
    let commit: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tên danh sách", text: $name)
            }
            .formStyle(.grouped)
            .navigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey(verb)) {
                        commit(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { name = initial }
    }
}
