// UpdateCheckerTests.swift — two layers of coverage:
//
//   1. `compareSemver` — pure version-string math, no I/O.
//   2. `check(fetch:currentVersion:)` — full pipeline with an injected
//      fetcher, exercising the 200 / 404 / >=400 / decode-error /
//      transport-error branches. The injected fetcher means these tests
//      never touch the network. See PRIVACY.md — the only real outbound
//      request is user-initiated from Settings → About → 检查更新.

import XCTest
@testable import CCGaugeBar

final class UpdateCheckerTests: XCTestCase {
    private let dummyURL = URL(string: "https://example.com/v1.0.0")!

    private func compare(_ current: String, _ latest: String) -> UpdateChecker.Result {
        UpdateChecker.compareSemver(current: current, latest: latest, releaseURL: dummyURL)
    }

    // MARK: - compareSemver

    func testEqualVersionsReportCurrent() {
        XCTAssertEqual(compare("1.0.0", "1.0.0"), .current(version: "1.0.0"))
    }

    func testNewerPatch() {
        if case .available(let v, _) = compare("1.0.0", "1.0.1") {
            XCTAssertEqual(v, "1.0.1")
        } else {
            XCTFail("1.0.1 > 1.0.0 should be .available")
        }
    }

    func testNewerMinorOverridesPatch() {
        if case .available(let v, _) = compare("1.0.9", "1.1.0") {
            XCTAssertEqual(v, "1.1.0")
        } else {
            XCTFail("1.1.0 > 1.0.9 should be .available")
        }
    }

    func testOlderLatestReportsCurrent() {
        XCTAssertEqual(compare("1.2.0", "1.1.0"), .current(version: "1.2.0"))
    }

    func testDifferentLengthVersionsPadWithZero() {
        // 1.0 == 1.0.0 (no available)
        XCTAssertEqual(compare("1.0.0", "1.0"), .current(version: "1.0.0"))
        // 1.0.0 < 1.0.0.1
        if case .available(let v, _) = compare("1.0.0", "1.0.0.1") {
            XCTAssertEqual(v, "1.0.0.1")
        } else {
            XCTFail("1.0.0.1 > 1.0.0 should be .available")
        }
    }

    func testPreReleaseSuffixIgnored() {
        // 1.0.1-beta vs 1.0.0 → 1.0.1 > 1.0.0 → available
        if case .available = compare("1.0.0", "1.0.1-beta") {
            // pass
        } else {
            XCTFail("1.0.1-beta should be treated as 1.0.1 and beat 1.0.0")
        }
    }

    // MARK: - check(fetch:currentVersion:) — pipeline branches

    /// A stable, real URL for the mock HTTPURLResponse. It's never actually
    /// hit — the fetcher closure is what produces the bytes — but
    /// HTTPURLResponse demands a URL on construction.
    private static let mockEndpoint = URL(string: "https://api.example.com/releases/latest")!

    private func httpResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: Self.mockEndpoint,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    func testFetch200WithNewerTagReportsAvailable() async {
        let body = Data(#"{"tag_name":"v1.0.1","html_url":"https://example.com/r/1.0.1"}"#.utf8)
        let response = httpResponse(200)
        let result = await UpdateChecker.check(
            fetch: { _ in (body, response) },
            currentVersion: "1.0.0"
        )
        guard case .available(let latest, let url) = result else {
            return XCTFail("expected .available, got \(result)")
        }
        XCTAssertEqual(latest, "1.0.1")
        XCTAssertEqual(url.absoluteString, "https://example.com/r/1.0.1")
    }

    func testFetch200WithSameTagReportsCurrent() async {
        let body = Data(#"{"tag_name":"v1.2.3","html_url":"https://example.com/r/1.2.3"}"#.utf8)
        let response = httpResponse(200)
        let result = await UpdateChecker.check(
            fetch: { _ in (body, response) },
            currentVersion: "1.2.3"
        )
        XCTAssertEqual(result, .current(version: "1.2.3"))
    }

    func testFetch200FallsBackToReleasesURLWhenHtmlURLMissing() async {
        // GitHub's API always returns html_url, but we defensively handle
        // its absence by falling back to the canonical releases page.
        let body = Data(#"{"tag_name":"v2.0.0"}"#.utf8)
        let response = httpResponse(200)
        let result = await UpdateChecker.check(
            fetch: { _ in (body, response) },
            currentVersion: "1.0.0"
        )
        guard case .available(_, let url) = result else {
            return XCTFail("expected .available, got \(result)")
        }
        XCTAssertEqual(url, UpdateChecker.releasesURL)
    }

    func testFetch200WithoutLeadingVStillCompares() async {
        // tag_name is "1.0.1" (no v prefix) — should still parse cleanly.
        let body = Data(#"{"tag_name":"1.0.1","html_url":"https://example.com/r/1.0.1"}"#.utf8)
        let response = httpResponse(200)
        let result = await UpdateChecker.check(
            fetch: { _ in (body, response) },
            currentVersion: "1.0.0"
        )
        guard case .available(let latest, _) = result else {
            return XCTFail("expected .available, got \(result)")
        }
        XCTAssertEqual(latest, "1.0.1")
    }

    func testFetch404ReportsCurrent() async {
        // GitHub returns 404 when the repo has no published releases yet.
        // We want this treated as "you're on the latest" rather than as an
        // error — there's nothing newer to install.
        let response = httpResponse(404)
        let result = await UpdateChecker.check(
            fetch: { _ in (Data(), response) },
            currentVersion: "1.0.0"
        )
        XCTAssertEqual(result, .current(version: "1.0.0"))
    }

    func testFetch500ReportsHTTPError() async {
        let response = httpResponse(500)
        let result = await UpdateChecker.check(
            fetch: { _ in (Data(), response) },
            currentVersion: "1.0.0"
        )
        XCTAssertEqual(result, .error("HTTP 500"))
    }

    func testFetch403ReportsHTTPError() async {
        // GitHub rate limits anonymous requests to 60/hr per IP with 403.
        let response = httpResponse(403)
        let result = await UpdateChecker.check(
            fetch: { _ in (Data(), response) },
            currentVersion: "1.0.0"
        )
        XCTAssertEqual(result, .error("HTTP 403"))
    }

    func testFetchMalformedJSONReportsError() async {
        let body = Data("definitely not JSON".utf8)
        let response = httpResponse(200)
        let result = await UpdateChecker.check(
            fetch: { _ in (body, response) },
            currentVersion: "1.0.0"
        )
        guard case .error = result else {
            return XCTFail("expected .error, got \(result)")
        }
    }

    func testFetchTransportErrorReportsError() async {
        struct FakeTransportError: LocalizedError {
            var errorDescription: String? { "the network is on fire" }
        }
        let result = await UpdateChecker.check(
            fetch: { _ in throw FakeTransportError() },
            currentVersion: "1.0.0"
        )
        XCTAssertEqual(result, .error("the network is on fire"))
    }
}
