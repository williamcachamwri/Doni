#if os(iOS)
import Foundation

/// Typography values resolved for MeloX's SwiftUI/CoreText lyric renderer.
///
/// The Music 26.6 UIKit specification stores a 48-point source font, but its
/// surrounding text-container geometry is not equivalent to assigning 48
/// points directly to `SynchronizedLyricText`. The rendered baseline therefore
/// stays close to `.largeTitle` instead of exposing that source value verbatim.
public struct AppleMusicLyricsTypographyProfile: Equatable, Sendable {
    public let primaryFontSize: Double

    public static let iOS26_6 = Self(
        primaryFontSize: 36
    )
}
#endif
