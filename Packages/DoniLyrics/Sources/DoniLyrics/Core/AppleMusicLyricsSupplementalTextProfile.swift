import Foundation

/// Reconstructed layout constants for Apple Music's transliteration and
/// translation layers. These values describe the iOS 26.6 implementation;
/// they are not public Apple API.
public struct AppleMusicLyricsSupplementalTextProfile: Equatable, Sendable {
    public let transliterationSpacing: Double
    public let transliterationMinimumWordSpacing: Double
    public let translationSpacing: Double
    public let translationBottomPadding: Double
    public let hiddenVerticalOffset: Double

    public static let iOS26_6 = Self(
        transliterationSpacing: 5,
        transliterationMinimumWordSpacing: 5,
        translationSpacing: 7,
        translationBottomPadding: 4,
        hiddenVerticalOffset: -20
    )
}
