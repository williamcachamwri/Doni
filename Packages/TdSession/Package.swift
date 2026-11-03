// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TdSession",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TdSession", targets: ["TdSession"])
    ],
    targets: [
        .target(name: "TdSession"),
        .testTarget(name: "TdSessionTests", dependencies: ["TdSession"])
    ]
)
