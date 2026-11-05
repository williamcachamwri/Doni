import Foundation

/// The app's own version numbers, and the arithmetic that says which one is newer.
///
/// Two numbers describe a build. `CFBundleShortVersionString` is what the About screen shows and
/// what a release tag has to match; `CFBundleVersion` carries the same version inside its digits —
/// `90 | major | minor | patch`, so `9010000` is 1.0.0 — which is how a build number on its own can
/// be compared with a GitHub tag without a second file being updated. The scheme is the reference's
/// (`MeloX/Core/Updates/AppVersion.swift`) with Doni's prefix, so a build number from another app
/// cannot be read as one of ours.
enum AppVersion {
    private static let prefix = 90

    static var marketing: String { Bundle.main.appVersion }
    static var build: String { Bundle.main.appBuildNumber }

    /// The version to show and to compare: the digits where they are ours, the marketing version
    /// when they are not.
    static var current: String { releaseVersion(fromBuildNumber: build) ?? marketing }

    /// `9110401` → `1.4.1`. A number without the prefix is not a Doni build number.
    static func releaseVersion(fromBuildNumber buildNumber: String) -> String? {
        guard let digits = Int(buildNumber), digits / 100_000 == prefix else { return nil }
        let body = digits % 100_000
        return "\((body / 10_000)).(((body % 10_000) / 100)).\(body % 100)"
    }

    /// Which of two versions is newer, ignoring a leading `v`, spacing, and any part the shorter
    /// one does not have — `1.2` and `1.2.0` are the same release.
    static func compare(_ lhs: String, to rhs: String) -> ComparisonResult {
        let left = parts(lhs), right = parts(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// A version without its tag decoration, for a screen that has to say `1.0.0` and not `v1.0.0`.
    static func displayName(_ version: String) -> String {
        version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
    }

    private static func parts(_ version: String) -> [Int] {
        version.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}

extension Bundle {
    var appVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var appBuildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
