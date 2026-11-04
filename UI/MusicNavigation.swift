import SwiftUI

/// The two ends of the zoom the reference gives a card that opens a music screen
/// (`MusicNavigationTransitions.swift:36-90`, `AppNavigation.swift:243-248`).
///
/// One namespace is shared by the whole tab bar, which is what lets a card in a shelf on one tab hand
/// its cover to a screen pushed on top of it. MeloX injects it through the environment
/// (`ContentView.swift:45`, `:393`) so no card has to be handed it; the destination reads the same
/// value. Without a namespace in scope both modifiers step aside and the push stays the system's
/// plain one, so a screen that never went through the shell still works.
private struct MusicNavigationNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var musicNavigationNamespace: Namespace.ID? {
        get { self[MusicNavigationNamespaceKey.self] }
        set { self[MusicNavigationNamespaceKey.self] = newValue }
    }
}

/// The id a card and the screen it opens agree on. MeloX builds it from the route
/// (`AppNavigation.swift:128-133`); Doni routes a playlist by its store id, so the string is the same
/// one with the same prefix.
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
