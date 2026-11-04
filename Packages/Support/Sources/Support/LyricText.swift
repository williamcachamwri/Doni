import Foundation

/// What a lyrics lookup can come back with, in the order the app has to treat them.
///
/// Both cases carry the text itself rather than a parsed shape: turning LRC into timed lines is
/// the lyrics screen's own parser, which is the one the user sees working.
public enum LyricText: Equatable, Sendable {
    /// LRC text with stamps in it. What the screen scrolls.
    case synced(String)
    /// Words without times, which the screen has to spread itself.
    case plain(String)
    /// Nothing found, which is a state the screen says out loud rather than an empty scroll.
    case none
}
