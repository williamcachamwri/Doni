// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Support",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Support", targets: ["Support"])
    ],
    targets: [
        .target(name: "Support"),
        .testTarget(name: "SupportTests", dependencies: ["Support"])
    ]
)
