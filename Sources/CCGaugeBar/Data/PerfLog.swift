// PerfLog.swift - lightweight timing instrumentation.
//
// All `log()` output goes to the macOS unified log via os.Logger so the
// user can `log stream --predicate 'subsystem == "dev.ccgauge.bar"'` or
// filter in Console.app — no need to relaunch with env vars to debug.
//
// `CCGAUGE_PERF=1` adds a parallel stderr trace for terminal-attached
// dev loops (e.g. `make run-debug`).

import Foundation
import os

public enum PerfLog {
    /// Subsystem matches CFBundleIdentifier; Console.app users can filter
    /// the whole app's logs with one predicate.
    private static let logger = Logger(subsystem: "dev.ccgauge.bar", category: "perf")

    private static var stderrEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["CCGAUGE_PERF"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    public static func log(_ message: String) {
        // Unified log: .debug is filtered out by default — visible in
        // Console.app when "Include Debug Messages" is on, or via
        // `log stream`. Marked .public because every caller here passes
        // a fixed-shape diagnostic message (file counts, timings, cache
        // generations) with no user data. **Anything that includes a
        // thrown `Error` description must go through `logError` instead**
        // — error messages routinely embed file paths or other PII.
        logger.debug("\(message, privacy: .public)")
        if stderrEnabled {
            FileHandle.standardError.write(Data("[ccgauge-bar][perf] \(message)\n".utf8))
        }
    }

    /// Errors get `.private` redaction on the error payload by default,
    /// so Console.app shows `[ccgauge-bar][perf] scan.error <private>`
    /// without leaking the user's filesystem paths to anyone shoulder-
    /// surfing the log stream. The leading `context` label stays public
    /// so the operator can still see WHERE the error came from.
    /// stderr fallback (gated by CCGAUGE_PERF) prints the full text — that
    /// stream is only attached when the dev runs `make run-debug` locally.
    public static func logError(_ context: String, _ error: Error) {
        let description = String(describing: error)
        logger.debug("\(context, privacy: .public) \(description, privacy: .private)")
        if stderrEnabled {
            FileHandle.standardError.write(Data("[ccgauge-bar][perf] \(context) \(description)\n".utf8))
        }
    }

    public static func measure<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let started = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
            log("\(label) \(String(format: "%.1f", ms))ms")
        }
        return try body()
    }

    public static func measureAsync<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let started = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
            log("\(label) \(String(format: "%.1f", ms))ms")
        }
        return try await body()
    }
}
