import Foundation
import SwiftUI

/// The three answers a version check can produce, shown the same way wherever one is asked.
///
/// It lives here rather than in `UI/` because both shells ask the same question and must give the same
/// sentence: the phone asks it when the listener opens the version row in Settings, the desktop asks it
/// on launch (`Mac/App/DesktopLaunchExperience.swift`).
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
