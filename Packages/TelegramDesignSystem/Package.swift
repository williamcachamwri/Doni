// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TelegramDesignSystem",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TelegramDesignSystem", targets: ["TelegramDesignSystem"])
    ],
    targets: [
        .target(name: "TelegramDesignSystem"),
        .testTarget(name: "TelegramDesignSystemTests", dependencies: ["TelegramDesignSystem"])
    ]
)
