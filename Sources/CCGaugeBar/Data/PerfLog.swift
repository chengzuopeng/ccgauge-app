// PerfLog.swift - lightweight stderr timing for the app's hot paths.

import Foundation

public enum PerfLog {
    private static var enabled: Bool {
        let value = ProcessInfo.processInfo.environment["CCGAUGE_PERF"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    public static func log(_ message: String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("[ccgauge-bar][perf] \(message)\n".utf8))
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
