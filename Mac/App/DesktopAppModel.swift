import Foundation
import Observation

/// The desktop's one owner of everything that is alive in this app.
///
/// The phone builds the same five objects in `DoniApp` as `@StateObject`s, because there a view is the
/// only thing that ever needs them. A desktop has three more: the menu bar's commands, the Dock's menu
/// and any window opened later, and none of those can hold a `@StateObject` — so they hang off a model
/// the app delegate owns, exactly as the reference does it (`DesktopAppModel.swift:6-24`).
///
/// The model hands the objects out by reference; it does not make them observable, and it must not try
/// to. Reactivity is the objects' own job: `DoniMacApp` injects them as environment objects, so a view
/// that draws playback state says `@EnvironmentObject var player: Player` and is invalidated by the
/// change rather than by a re-render of everything above it.
@MainActor
@Observable
final class DesktopAppModel {
    let session = TelegramSession()
    let indexer = LibraryIndexer()
    let library = Library.shared
    let artwork = CoverArtwork.shared
    let player = Player(library: .shared)
    /// Saved Messages, which is Cloud Music's whole library. The phone builds one per screen; the
    /// desktop keeps the one, because the sidebar's footer and the pane have to agree about what is
    /// uploading.
    let cloud = CloudMusic()
    let ui = DesktopUIState()

    /// Whether the first `bootstrap()` has run. One restore per launch, however many views ask for it —
    /// the same rule `Player.hasRestoredPlayback` holds on the phone (`Player.swift:102`).
    @ObservationIgnored private var hasBootstrapped = false

    /// The one thing the shell has to do before any pane exists: put back the position the listener
    /// stopped at. On the phone this is the library tab's job, the first pane that ever needs it
    /// (`UI/LibraryView.swift:110`); a desktop that waits for a pane it does not have yet is a desktop
    /// that silently never resumes.
    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        player.restore()
    }

    /// TDLib has said who this is, and two things follow — neither of them optional, and neither of
    /// them visible on screen: the player cannot stream a single byte without a downloader, because
    /// `Player.stream` opens with `guard let downloader`, and nothing appears in the library until the
    /// walk has read the chats.
    func sessionDidBecomeAuthorized() {
        player.bind(session.covers())
        indexer.run(session, library: library)
    }

    /// The four reactions a session ending has to have, in the order the phone runs them
    /// (`UI/SettingsView.swift:478-490`): nothing may write rows while the files are being thrown away,
    /// and nothing may keep showing the rows that were written.
    private func endSession() async -> Bool {
        indexer.reset()
        player.stop()
        // Awaited rather than fired off: the answer says whether the files actually went, and the rest
        // of the sign-out is only worth doing once that is known.
        let wiped = await library.wipe()
        _ = artwork.clearCache()
        return wiped
    }

    /// A session ending somewhere else is the one event no screen can see: TDLib announces it only to
    /// the client. Without this hook a Mac would keep playing, keep indexing and leave the rows readable
    /// in `library.db` — the defect that started this port.
    func installTeardown() {
        session.onSessionEnded = { [weak self] in
            guard let self else { return }
            _ = await self.endSession()
        }
    }

    /// The button's path, which is the phone's: promise the deletion before asking for the logout, so
    /// nothing can leave the app between the two and take the promise with it.
    func signOut() async {
        let wiped = await endSession()
        session.logOut()
        if !wiped {
            // `wipe` left its own flag for the next launch to finish, so this is not a leak that will be
            // forgotten — but the listener was promised a clean slate and deserves to hear it is not one.
            session.noteCleanupPending(
                "Chưa xoá hết dữ liệu trên máy — Doni sẽ thử lại khi bạn mở app")
        }
    }
}
