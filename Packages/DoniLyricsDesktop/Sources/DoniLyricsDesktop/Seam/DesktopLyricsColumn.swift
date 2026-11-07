import DoniLyrics
import SwiftUI

/// The one public door into the copied desktop column.
///
/// Every file under `Features/` and `Core/` in this package is the reference's own source, kept at
/// internal access so the transcription stays byte-for-byte. This wrapper is the seam: the only
/// place the app is allowed to ask for the desktop lyrics, and the only file here that is not a copy.
///
/// It also owns the environment the copied views read. They want `@Environment(DesktopAppModel.self)`,
/// and Doni's Mac app already has a `DesktopAppModel` of its own for the whole window — so the two
/// can never be injected from the app target, where the local name would win. Building it in here is
/// what keeps both spellings alive: the app hands over plain objects, this module resolves the name.
///
/// The two forms are the reference's split, not a new one — `DesktopPlayerInspector.swift:11-18`
/// asks for the compact column with lyric blur off, and the full-window player asks for the wide
/// column with blur left on.
public struct DesktopLyricsColumn: View {
    private let compact: Bool
    private let allowsLyricBlur: Bool
    private let isActive: Bool
    private let focusLift: CGFloat
    private let store: PlayerStore
    private let words: DesktopLyricsModel
    private let settings: AppSettings

    public init(compact: Bool,
                allowsLyricBlur: Bool,
                isActive: Bool,
                focusLift: CGFloat = 0,
                player: PlayerStore,
                lyrics: DesktopLyricsModel,
                settings: AppSettings) {
        self.compact = compact
        self.allowsLyricBlur = allowsLyricBlur
        self.isActive = isActive
        self.focusLift = focusLift
        self.store = player
        self.words = lyrics
        self.settings = settings
    }

    public var body: some View {
        DesktopPlaybackPositionedLyricsView(compact: compact,
                                            allowsLyricBlur: allowsLyricBlur,
                                            isActive: isActive,
                                            focusLift: focusLift)
            .environment(store)
            .environment(settings)
            .environment(model)
    }

    /// Built per render on purpose: `@Observable` classes are reference types, so this is a fresh
    /// wrapper over the same three objects rather than a second copy of their state.
    private var model: DesktopAppModel {
        DesktopAppModel(player: store, lyrics: words, settings: settings)
    }
}
