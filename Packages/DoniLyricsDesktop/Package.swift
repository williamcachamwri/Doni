// swift-tools-version:6.2
import PackageDescription

// The desktop lyrics column, transcribed from the reference app's own `MeloXDesktop`
// target. It is a second package rather than more files in `DoniLyrics` because the
// reference keeps its two lyrics renderers in two targets, and its desktop files name
// their types the same way its iOS files do — `SynchronizedLyricText`,
// `DesktopLyricLineView`'s row metrics, the motion profiles. One module cannot hold
// both spellings of a name, so the copied desktop lines get a module of their own.
//
// What is *not* copied is the model. Every type the desktop column needs that
// `DoniLyrics` already owns — `LyricLine`, `LyricInterlude`, `LyricPlaybackTimeline`,
// `AppleMusicLyricsMotionProfile`, `AppSettings`, `PlayerStore` — is imported from
// there, so a lyric parsed once is a lyric read by both shells. Where the desktop
// column asks for a member the shared type does not have, the shared type gains it;
// that is the difference between this and the reference, which duplicates 112 files
// across its targets and has to fix every later change twice.
let package = Package(
    name: "DoniLyricsDesktop",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DoniLyricsDesktop", targets: ["DoniLyricsDesktop"])
    ],
    dependencies: [
        .package(name: "Support", path: "../Support"),
        .package(name: "DoniLyrics", path: "../DoniLyrics")
    ],
    targets: [
        .target(
            name: "DoniLyricsDesktop",
            dependencies: [
                .product(name: "Support", package: "Support"),
                .product(name: "DoniLyrics", package: "DoniLyrics")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
