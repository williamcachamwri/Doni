import SwiftUI

/// The three answers a version check can produce, shown the same way wherever one is asked.
struct UpdateAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let releaseURL: URL?

    static func available(_ result: AppUpdateResult, version: String) -> UpdateAlert {
        UpdateAlert(
            title: "Có bản mới",
            message: localized("Hiện tại %@, bản mới nhất %@. Mở trang phát hành để xem nội dung.",
                               version, AppVersion.displayName(result.latestVersion)),
            releaseURL: result.releaseURL
        )
    }

    static func current(version: String) -> UpdateAlert {
        UpdateAlert(title: "Đã là bản mới nhất",
                    message: localized("Phiên bản %@ là mới nhất.", version), releaseURL: nil)
    }

    static func failed(_ error: Error) -> UpdateAlert {
        UpdateAlert(title: "Kiểm tra cập nhật thất bại",
                    message: (error as? AppUpdateError).map(\.message) ?? "\(error)",
                    releaseURL: nil)
    }
}

extension View {
    /// The alert a check answers with. The release-page button appears only when a URL exists, so
    /// "up to date" and "check failed" get one button rather than a dead link.
    func updateAlert(_ alert: Binding<UpdateAlert?>) -> some View {
        modifier(UpdateAlertModifier(alert: alert))
    }

    /// Once per launch: show the release notes of a version this phone has not seen, then ask GitHub
    /// whether a newer build exists. Both are one-shot, and a failed check stays silent.
    func appLaunchChecks() -> some View { modifier(AppLaunchModifier()) }
}

private struct UpdateAlertModifier: ViewModifier {
    @Binding var alert: UpdateAlert?
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert(LocalizedStringKey(alert?.title ?? ""),
                      isPresented: presented, presenting: alert) { shown in
            if let url = shown.releaseURL {
                Button("Mở trang phát hành") { openURL(url) }
                Button("Để sau", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { shown in
            Text(shown.message)
        }
    }

    private var presented: Binding<Bool> {
        Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })
    }
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
