// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TdBridge",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TdBridge", targets: ["TdBridge"])
    ],
    targets: [
        .binaryTarget(
            name: "TdLibXCFramework",
            path: "../../Vendor/td/tdlib.xcframework"
        ),
        .target(
            name: "TdBridge",
            dependencies: ["TdLibXCFramework"],
            linkerSettings: [
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("UIKit"),
                .linkedLibrary("iconv"),
                .linkedLibrary("resolv"),
                .linkedLibrary("z"),
                .linkedLibrary("c++")
            ]
        )
    ]
)
