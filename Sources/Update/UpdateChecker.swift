import AppKit
import Foundation
import os

/// Checks GitHub Releases for a newer build and points the user at the download.
/// Distribution is a manually-installed DMG, so this never self-installs — it
/// surfaces that an update exists and opens the asset/release page.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    private static let log = Logger(subsystem: "com.zkwokleung.shortcutwheel", category: "update")
    private static let lastCheckKey = "lastUpdateCheck"

    struct Release: Equatable {
        let version: String
        let tagName: String
        let notes: String
        let pageURL: URL
        let dmgURL: URL?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    let currentVersion: String

    private let endpoint: URL
    private let throttle: TimeInterval
    private let defaults: UserDefaults
    private let fetch: (URL) async throws -> Data

    /// `fetch` is injectable so tests can supply a canned GitHub payload without
    /// hitting the network, mirroring `ConfigStore`'s injectable `fileURL`.
    init(
        endpoint: URL = URL(string: "https://api.github.com/repos/zkwokleung/shortcut-wheel/releases/latest")!,
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        throttle: TimeInterval = 24 * 60 * 60,
        defaults: UserDefaults = .standard,
        fetch: @escaping (URL) async throws -> Data = UpdateChecker.defaultFetch
    ) {
        self.endpoint = endpoint
        self.currentVersion = currentVersion
        self.throttle = throttle
        self.defaults = defaults
        self.fetch = fetch
        self.lastChecked = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    /// Fetches the latest release. Auto-checks (`userInitiated == false`) are skipped
    /// while still inside the throttle window so launch never spams GitHub.
    func check(userInitiated: Bool) async {
        if !userInitiated, let last = lastChecked, Date().timeIntervalSince(last) < throttle {
            return
        }
        state = .checking
        do {
            let data = try await fetch(endpoint)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data).release

            let now = Date()
            lastChecked = now
            defaults.set(now, forKey: Self.lastCheckKey)

            if let remote = SemanticVersion(release.version),
               let local = SemanticVersion(currentVersion),
               remote > local {
                state = .available(release)
                Self.log.info("Update available: \(release.version, privacy: .public) (current \(self.currentVersion, privacy: .public))")
            } else {
                state = .upToDate
                Self.log.info("Up to date at \(self.currentVersion, privacy: .public)")
            }
        } catch {
            state = .failed(error.localizedDescription)
            Self.log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func openDownload(_ release: Release) {
        NSWorkspace.shared.open(release.dmgURL ?? release.pageURL)
    }

    private static func defaultFetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ShortcutWheel", forHTTPHeaderField: "User-Agent") // GitHub rejects requests without one
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.http(http.statusCode)
        }
        return data
    }
}

private enum UpdateError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "GitHub returned HTTP \(code)."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }

    var release: UpdateChecker.Release {
        let dmg = assets.first { $0.browserDownloadURL.lowercased().hasSuffix(".dmg") }
        let version = tagName.first == "v" ? String(tagName.dropFirst()) : tagName
        return UpdateChecker.Release(
            version: version,
            tagName: tagName,
            notes: body ?? "",
            pageURL: URL(string: htmlURL) ?? URL(string: "https://github.com/zkwokleung/shortcut-wheel/releases")!,
            dmgURL: dmg.flatMap { URL(string: $0.browserDownloadURL) }
        )
    }
}
