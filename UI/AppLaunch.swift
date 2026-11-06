import SwiftUI

extension View {
    /// Once per launch: show the release notes of a version this phone has not seen, then ask GitHub
    /// whether a newer build exists. Both are one-shot, and a failed check stays silent.
    ///
    /// The alert itself is shared with the desktop (`App/UpdateAlert.swift`); what is not shared is the
    /// notes sheet, because a phone's release notes are a full-screen page and a Mac's are not.
    func appLaunchChecks() -> some View { modifier(AppLaunchModifier()) }
}

private struct AppLaunchModifier: ViewModifier {
    @State private var notes = AppReleaseNotes.load()
    @State private var showsNotes = false
    @State private var alert: UpdateAlert?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showsNotes) {
                NavigationStack {
                    ReleaseNotesView(notes: notes)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Bắt đầu") { showsNotes = false }
                            }
                        }
                }
            }
            .updateAlert($alert)
            .task { await run() }
    }

    private func run() async {
        guard AppReleaseNotesStore.shouldPresent(notes) else { return }
        AppReleaseNotesStore.markPresented(notes)
        showsNotes = true
        guard AppUpdateSettings.checksOnLaunch else { return }
        do {
            let result = try await AppUpdateService.check()
            if result.hasUpdate { alert = .available(result, version: AppVersion.current) }
        } catch {
            // Intentionally silent: a failed check stays the app's problem, not the listener's.
        }
    }
}
