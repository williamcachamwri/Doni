import SwiftUI

/// The two ends of the zoom the reference gives a card that opens a music screen
/// (`MusicNavigationTransitions.swift:36-90`, `AppNavigation.swift:243-248`).
/// One namespace is shared by the whole tab bar and injected through the environment, as in MeloX
/// (`ContentView.swift:45`, `:393`). With none in scope both modifiers step aside, so a screen outside
/// the shell still gets the system's plain push.
private struct MusicNavigationNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var musicNavigationNamespace: Namespace.ID? {
        get { self[MusicNavigationNamespaceKey.self] }
        set { self[MusicNavigationNamespaceKey.self] = newValue }
    }
}

/// The id a card and the screen it opens agree on: MeloX's route string (`AppNavigation.swift:128-133`)
/// built from Doni's playlist store id.
enum MusicNavigationTransition {
    static func playlist(_ id: Int64) -> String {
        "playlist-\(id)"
    }
}

extension View {
    /// The card end of the zoom.
    func musicMatchedTransitionSource(playlistID: Int64) -> some View {
        modifier(MusicMatchedTransitionSourceModifier(playlistID: playlistID))
    }

    /// The screen end, which is where the system reads what to grow.
    func musicNavigationTransition(playlistID: Int64) -> some View {
        modifier(MusicNavigationTransitionModifier(playlistID: playlistID))
    }
}

private struct MusicMatchedTransitionSourceModifier: ViewModifier {
    let playlistID: Int64

    @Environment(\.musicNavigationNamespace) private var namespace

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(
                id: MusicNavigationTransition.playlist(playlistID), in: namespace
            )
        } else {
            content
        }
    }
}

private struct MusicNavigationTransitionModifier: ViewModifier {
    let playlistID: Int64

    @Environment(\.musicNavigationNamespace) private var namespace

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(
                .zoom(sourceID: MusicNavigationTransition.playlist(playlistID), in: namespace)
            )
        } else {
            content
        }
    }
}
