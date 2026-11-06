import AppKit
import SwiftUI

/// The two questions the reference asks of a listener the moment the window appears
/// (`DesktopLaunchExperience.swift:4-8`), in Doni's own answers.
///
/// On the phone the equivalent is `appLaunchChecks()` — release notes, then a version check. The desktop
/// keeps the version check and drops the notes sheet, because a Mac's release notes belong in the About
/// window that does not exist yet; what it adds is the clipboard, which is a thing people do on a
/// keyboard and nobody does on a phone.
extension View {
    func desktopLaunchExperience() -> some View {
        modifier(DesktopLaunchExperienceModifier())
    }
}

private struct DesktopLaunchExperienceModifier: ViewModifier {
    @Environment(DesktopAppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// One look per launch, however many times the app comes back to the front: asking twice about the
    /// same clipboard text is how a helper starts feeling like a nag.
    @State private var hasInspectedClipboard = false
    @State private var hasCheckedForUpdates = false
    @State private var detectedHandle: String?
    @State private var update: UpdateAlert?
    @State private var resolutionFailure: String?

    func body(content: Content) -> some View {
        content
            .task {
                inspectClipboardIfNeeded()
                await checkForUpdatesIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                inspectClipboardIfNeeded()
            }
            .alert("Kênh trong clipboard", isPresented: detectedPresented) {
                Button("Thêm kênh") { addDetectedChannel() }
                Button("Bỏ qua", role: .cancel) { detectedHandle = nil }
            } message: {
                Text(localized("Thấy %@ trong clipboard. Thêm vào thư viện?", detectedHandle ?? ""))
            }
            .alert("Không thêm được kênh", isPresented: failurePresented) {
                Button("OK", role: .cancel) { resolutionFailure = nil }
            } message: {
                Text(resolutionFailure ?? "")
            }
            .updateAlert($update)
    }

    private var detectedPresented: Binding<Bool> {
        Binding(
            get: { detectedHandle != nil },
            set: { if !$0 { detectedHandle = nil } }
        )
    }

    private var failurePresented: Binding<Bool> {
        Binding(
            get: { resolutionFailure != nil },
            set: { if !$0 { resolutionFailure = nil } }
        )
    }

    private func inspectClipboardIfNeeded() {
        guard !hasInspectedClipboard, scenePhase == .active,
              model.session.isAuthorized else {
            return
        }
        hasInspectedClipboard = true

        guard let text = NSPasteboard.general.string(forType: .string),
              let handle = TelegramLink.channelHandle(in: text),
              !model.library.channels.contains(where: {
                  $0.username.compare(handle, options: .caseInsensitive) == .orderedSame
              }) else {
            return
        }
        detectedHandle = handle
    }

    /// Resolve, write the row down, then start the walk over — the same three steps the phone's
    /// add-channel sheet runs (`UI/AddChannelSheet.swift:193`, `UI/LibraryView.swift:128`), because a
    /// channel that is in the list but never read is a channel the library does not have.
    private func addDetectedChannel() {
        guard let handle = detectedHandle else { return }
        detectedHandle = nil
        guard let reader = model.session.reader() else { return }
        let books = model.library, walk = model.indexer, session = model.session, ui = model.ui
        Task {
            do {
                books.add(try await reader.channel(username: handle))
                walk.run(session, library: books)
                ui.selection = .channels
            } catch {
                // The handle was a channel once; a rename or a ban is the usual reason it is not now.
                resolutionFailure = LibraryIndexer.describe(error)
            }
        }
    }

    private func checkForUpdatesIfNeeded() async {
        guard !hasCheckedForUpdates, AppUpdateSettings.checksOnLaunch else { return }
        hasCheckedForUpdates = true
        do {
            let result = try await AppUpdateService.check()
            if result.hasUpdate {
                update = .available(result, version: AppVersion.current)
            }
        } catch {
            // A failed check stays the app's problem, not the listener's — the phone's rule, kept.
        }
    }
}

/// The three shapes a channel link is actually copied in.
private enum TelegramLink {
    /// `https://t.me/qishuiyinl`, `t.me/qishuiyinl` and `@qishuiyinl` come out of Telegram's own share
    /// sheet; anything else the clipboard holds is somebody's sentence and the app has no business
    /// asking about it. A trailing message number (`t.me/qishuiyinl/1234`) is dropped — the link is
    /// worth adding, the post is not what is being offered.
    static func channelHandle(in text: String) -> String? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www."] where candidate.hasPrefix(prefix) {
            candidate = String(candidate.dropFirst(prefix.count))
        }
        if candidate.hasPrefix("@") {
            candidate = String(candidate.dropFirst())
        } else if candidate.hasPrefix("t.me/") || candidate.hasPrefix("telegram.me/") {
            let host = candidate.hasPrefix("t.me/") ? "t.me/" : "telegram.me/"
            candidate = String(candidate.dropFirst(host.count))
        } else {
            return nil
        }
        let handle = String(candidate.split(separator: "/").first ?? "")
        guard handle.count >= Self.minimumHandleLength,
              handle.count <= 32,
              handle.first?.isLetter == true,
              handle.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return nil
        }
        return handle
    }

    /// Telegram's own floor for a username; shorter strings are somebody's abbreviation, not a channel.
    private static let minimumHandleLength = 5
}
