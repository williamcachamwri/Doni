import Foundation

/// What one published release says about itself.
struct AppUpdateResult: Equatable, Sendable {
    let currentVersion: String
    let latestVersion: String
    let releaseName: String
    let releaseURL: URL
    let publishedAt: Date?

    var hasUpdate: Bool {
        AppVersion.compare(latestVersion, to: currentVersion) == .orderedDescending
    }
}

enum AppUpdateError: Error, Equatable {
    /// The repository has no published release yet — the normal answer before the first tag.
    case noRelease
    /// A release came back without the two things a reader needs: a tag and a page to open.
    case invalidRelease

    var message: String {
        switch self {
        case .noRelease: return localized("Chưa có bản phát hành nào.")
        case .invalidRelease: return localized("Thông tin phát hành không đầy đủ.")
        }
    }
}

/// GitHub Releases, asked the way the reference asks it.
///
/// The list endpoint rather than `/releases/latest`, because the newest published release is not
/// always the one to offer — a draft or a pre-release is newer than what anybody should be told to
/// install, and a repository that has just been made has no releases at all, which is an answer
/// rather than a failure.
///
/// Nothing is downloaded and nothing is installed: an app signed with a free personal team cannot
/// replace itself, so the honest outcome is a sentence and a link to the release page.
enum AppUpdateService {
    static let repositoryURL = URL(string: "https://github.com/williamcachamwri/Doni")!

    private static let releasesURL = URL(
        string: "https://api.github.com/repos/williamcachamwri/Doni/releases?per_page=100"
    )!

    /// The newest release that is actually out. Throws `noRelease` when the repository has none,
    /// which is what a first launch before the first tag looks like.
    static func check(currentVersion: String = AppVersion.current) async throws -> AppUpdateResult {
        var request = URLRequest(url: releasesURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Doni", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { throw AppUpdateError.noRelease }
        guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let releases = try decoder.decode([GitHubRelease].self, from: data)
        guard let release = releases.first(where: { !$0.draft && !$0.prerelease }) else {
            throw AppUpdateError.noRelease
        }
        let latest = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latest.isEmpty, let page = URL(string: release.htmlURL) else {
            throw AppUpdateError.invalidRelease
        }
        return AppUpdateResult(currentVersion: currentVersion, latestVersion: latest,
                               releaseName: release.name.flatMap { $0.isEmpty ? nil : $0 } ?? latest,
                               releaseURL: page, publishedAt: release.publishedAt)
    }

    /// The four fields of the API payload this app reads
    /// (`rest.github.com` — `tag_name`, `name`, `html_url`, `published_at`).
    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: String
        let publishedAt: Date?
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case draft
            case prerelease
        }
    }
}

/// Whether the next launch is allowed to ask GitHub for a newer version.
///
/// Default on, like the reference: a listener who installed the app from a release page wants to
/// know when there is another one, and a check that fails quietly is not a reason to interrupt them.
enum AppUpdateSettings {
    private static let key = "updates.checkOnLaunch"

    static var checksOnLaunch: Bool {
        get {
            guard UserDefaults.standard.object(forKey: key) != nil else { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
