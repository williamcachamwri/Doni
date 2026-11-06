// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TdBridge",
    platforms: [.iOS(.v17), .macOS(.v14)],
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
                // Scoped because UIKit does not exist on macOS, and the archives
                // reference no Objective-C class at all — `nm -u` on the merged
                // library is empty of `_OBJC_CLASS_$_*`, so this is only here for
                // what the iOS link line already assumed.
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedLibrary("iconv"),
                .linkedLibrary("resolv"),
                .linkedLibrary("z"),
                .linkedLibrary("c++")
            ]
        )
    ]
)
