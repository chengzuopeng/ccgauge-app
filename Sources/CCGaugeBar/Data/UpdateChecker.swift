// UpdateChecker.swift — fetches the latest published release tag from
// GitHub and compares it to the bundle's own version.
//
// This is the ONE place ccgauge-bar makes a deliberate outbound HTTP
// request, and it only fires when the user explicitly clicks
// "Check for updates" in Settings → About. See PRIVACY.md.

import Foundation

public enum UpdateChecker {
    public static let repoOwner = "chengzuopeng"
    public static let repoName = "ccgauge-app"

    public static var releasesURL: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
    }

    public enum Result: Equatable, Sendable {
        case current(version: String)
        case available(latest: String, releaseURL: URL)
        case error(String)
    }

    /// Pluggable HTTP transport — the production default routes through
    /// `URLSession.shared`; tests inject a closure that returns canned
    /// `(Data, HTTPURLResponse)` pairs so we can exercise 200 / 404 / 500 /
    /// malformed-JSON / network-error branches without touching the
    /// network. Signature matches `URLSession.data(for:)` so swapping is
    /// trivial.
    public typealias Fetcher = (URLRequest) async throws -> (Data, URLResponse)

    /// Compare the bundle's CFBundleShortVersionString against the latest
    /// GitHub release tag (`tag_name`, strip leading `v`). User-initiated;
    /// no caching or background polling.
    ///
    /// - Parameters:
    ///   - fetch: HTTP transport. Defaults to `URLSession.shared.data(for:)`.
    ///     Tests pass a closure that returns canned responses.
    ///   - currentVersion: Override for the bundle version. Defaults to
    ///     `Bundle.main`'s `CFBundleShortVersionString`. Tests pass an
    ///     explicit version so they don't depend on whatever Xcode happens
    ///     to inject into the test bundle.
    public static func check(
        fetch: Fetcher = { try await URLSession.shared.data(for: $0) },
        currentVersion: String? = nil
    ) async -> Result {
        let current = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "0.0.0"
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // GitHub's REST API expects an Accept header for stable JSON shapes.
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Identify ourselves — GitHub blocks anonymous requests without UA.
        request.setValue("ccgauge-bar/\(current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await fetch(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                // Repository has no releases yet → treat as "current".
                return .current(version: current)
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                return .error("HTTP \(http.statusCode)")
            }
            struct Release: Decodable {
                let tag_name: String
                let html_url: String?
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst())
                : release.tag_name
            let releaseURL = URL(string: release.html_url ?? releasesURL.absoluteString) ?? releasesURL
            return compareSemver(current: current, latest: latest, releaseURL: releaseURL)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Naive semver comparison (major.minor.patch). Treats pre-release
    /// suffixes lexicographically; good enough for ccgauge-bar's release
    /// cadence (no rapid-fire pre-release tags).
    static func compareSemver(current: String, latest: String, releaseURL: URL) -> Result {
        let c = parseVersion(current)
        let l = parseVersion(latest)
        if isGreater(l, than: c) {
            return .available(latest: latest, releaseURL: releaseURL)
        }
        return .current(version: current)
    }

    /// Lexicographic compare on padded version tuples. `[1, 2] > [1, 1, 9]`
    /// because 2 > 1 at the second slot. Treats missing slots as 0.
    private static func isGreater(_ a: [Int], than b: [Int]) -> Bool {
        let length = Swift.max(a.count, b.count)
        for i in 0..<length {
            let lhs = i < a.count ? a[i] : 0
            let rhs = i < b.count ? b[i] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func parseVersion(_ s: String) -> [Int] {
        s.split(separator: "-").first.map(String.init).map { core in
            core.split(separator: ".").map { Int($0) ?? 0 }
        } ?? [0]
    }
}
