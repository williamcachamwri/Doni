import SwiftUI

/// The three answers a version check can produce, presented the same way wherever one is asked.
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
    /// The alert a check answers with. A release page is offered only when there is one to open, so
    /// "you are up to date" and "the check failed" get a single button rather than a dead link.
    func updateAlert(_ alert: Binding<UpdateAlert?>) -> some View {
        modifier(UpdateAlertModifier(alert: alert))
    }

    /// What the app does once per launch: show the notes of a version this phone has not seen, and
    /// ask GitHub whether a newer one exists.
    ///
    /// Both are one-shot by construction. A sheet that returns on every launch is dismissed without
    /// being read, and the automatic check is silent on failure — an app that interrupts a listener
    /// because its own network is down has made the network somebody else's problem.
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
            // Nothing to say: the check is a courtesy, and a failed one is not the listener's news.
        }
    }
}
