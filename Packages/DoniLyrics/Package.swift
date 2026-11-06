// swift-tools-version:6.2
import PackageDescription

// The lyrics screen is transcribed from the reference app's own SwiftUI sources.
// That transcription is useful only if it stays verbatim, so it cannot live in the
// app target: the app is Swift 6 with complete concurrency checking and every
// warning is an error, while the reference is written in Swift 5 mode. A separate
// package is the one place the copied lines can be left exactly as they were found.
let package = Package(
    name: "DoniLyrics",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "DoniLyrics", targets: ["DoniLyrics"])
    ],
    dependencies: [
        .package(name: "Support", path: "../Support")
    ],
    targets: [
        .target(
            name: "DoniLyrics",
            dependencies: [
                .product(name: "Support", package: "Support")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
