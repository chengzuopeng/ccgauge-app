// ScanEngine.swift - background actor for JSONL indexing and snapshot rebuilds.

import Foundation

public struct ScanUpdate: Sendable {
    public let result: ScanResult
    public let changed: Bool
    public let summary: String
}

public struct ReconcileCacheUpdate: Sendable {
    public let changed: Bool
    public let started: Date
    public let summary: String
}

public actor ScanEngine {
    private struct Job: Sendable {
        let url: URL
        let source: ProviderId
    }

    private struct JobResult: Sendable {
        let path: String
        let entry: ScanFileEntry
        let reused: Bool
    }

    private var cache: [String: ScanFileEntry] = [:]
    private var snapshot: ScanResult?
    private var persistTask: Task<Void, Never>?
    private static let maxScanConcurrency = 6

    public init() {}

    public func loadPersistedSnapshot() async -> ScanUpdate? {
        guard cache.isEmpty, snapshot == nil else { return nil }

        let loaded = ScanIndexPersistence.load()
        guard !loaded.isEmpty else { return nil }

        let started = Date()
        cache = loaded
        let dirs = providerDirs()
        let result = buildSnapshot(started: started,
                                   claudeDirs: dirs.claude,
                                   codexDirs: dirs.codex)
        snapshot = result
        return ScanUpdate(
            result: result,
            changed: true,
            summary: "persisted files=\(loaded.count) records=\(result.stats.assistantRecords)"
        )
    }

    public func scan(force: Bool = false) async throws -> ScanUpdate {
        try await PerfLog.measureAsync(force ? "scan.force" : "scan.incremental") {
            try await scanImpl(force: force)
        }
    }

    public func reconcileCache(paths rawPaths: [String]) async throws -> ReconcileCacheUpdate? {
        let paths = normalizedJsonlPaths(rawPaths)
        guard !paths.isEmpty else { return nil }

        return try await PerfLog.measureAsync("scan.reconcile.cache paths=\(paths.count)") {
            try await reconcileCacheImpl(paths: paths)
        }
    }

    public func rebuildSnapshot(started: Date, summary: String) -> ScanUpdate {
        let dirs = providerDirs()
        let result = buildSnapshot(started: started,
                                   claudeDirs: dirs.claude,
                                   codexDirs: dirs.codex)
        snapshot = result
        return ScanUpdate(
            result: result,
            changed: true,
            summary: "\(summary) records=\(result.stats.assistantRecords)"
        )
    }

    public func reconcile(paths rawPaths: [String]) async throws -> ScanUpdate? {
        guard let update = try await reconcileCache(paths: rawPaths) else {
            if let snapshot { return ScanUpdate(result: snapshot, changed: false, summary: "no-jsonl-paths") }
            return nil
        }
        guard update.changed else {
            if let snapshot { return ScanUpdate(result: snapshot, changed: false, summary: update.summary) }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        return rebuildSnapshot(started: update.started, summary: update.summary)
    }

    // MARK: - Full incremental scan

    private func scanImpl(force: Bool) async throws -> ScanUpdate {
        let started = Date()
        let claudeDirs = ClaudeParser.dirs()
        let codexDirs = CodexParser.dirs()

        let claudeFiles = PerfLog.measure("enumerate.claude") {
            enumerateJsonl(dirs: claudeDirs)
        }
        let codexFiles = PerfLog.measure("enumerate.codex") {
            enumerateJsonl(dirs: codexDirs)
        }

        var jobs: [Job] = []
        jobs.reserveCapacity(claudeFiles.count + codexFiles.count)
        for f in claudeFiles { jobs.append(Job(url: f, source: .claude)) }
        for f in codexFiles { jobs.append(Job(url: f, source: .codex)) }

        let cacheSnapshot = force ? [:] : cache
        var newCache: [String: ScanFileEntry] = [:]
        newCache.reserveCapacity(jobs.count)

        var parsedFiles = 0
        var reusedFiles = 0

        try await withThrowingTaskGroup(of: JobResult.self) { group in
            var nextIndex = 0
            let initialCount = min(Self.maxScanConcurrency, jobs.count)

            for _ in 0..<initialCount {
                let job = jobs[nextIndex]
                nextIndex += 1
                group.addTask {
                    try await Self.processJob(job, cached: cacheSnapshot[normalizePath(job.url.path)])
                }
            }

            while let result = try await group.next() {
                newCache[result.path] = result.entry
                if result.reused { reusedFiles += 1 } else { parsedFiles += 1 }

                if nextIndex < jobs.count {
                    let job = jobs[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        try await Self.processJob(job, cached: cacheSnapshot[normalizePath(job.url.path)])
                    }
                }
            }
        }

        let oldPaths = Set(cacheSnapshot.keys)
        let newPaths = Set(newCache.keys)
        let changed = force || snapshot == nil || parsedFiles > 0 || oldPaths != newPaths

        if !changed, let snapshot {
            PerfLog.log("scan.unchanged files=\(newCache.count) reused=\(reusedFiles)")
            cache = newCache
            return ScanUpdate(result: snapshot, changed: false, summary: "unchanged")
        }

        cache = newCache
        let result = buildSnapshot(started: started,
                                   claudeDirs: claudeDirs,
                                   codexDirs: codexDirs)
        snapshot = result
        schedulePersist()

        return ScanUpdate(
            result: result,
            changed: true,
            summary: "files=\(result.stats.filesScanned) parsedFiles=\(parsedFiles) reusedFiles=\(reusedFiles) records=\(result.stats.assistantRecords)"
        )
    }

    // MARK: - Path-level reconcile

    private func reconcileCacheImpl(paths: [String]) async throws -> ReconcileCacheUpdate? {
        let started = Date()
        var changed = false
        var parsedFiles = 0
        var removedFiles = 0
        var unchangedFiles = 0

        for path in paths {
            guard let source = sourceForPath(path) else { continue }

            guard let attrs = try? fileAttrs(path) else {
                if cache.removeValue(forKey: path) != nil {
                    changed = true
                    removedFiles += 1
                }
                continue
            }

            if let cached = cache[path],
               cached.parserVersion == ScanParserVersions.current(for: source),
               cached.mtimeMs == attrs.mtimeMs,
               cached.size == attrs.size {
                unchangedFiles += 1
                continue
            }

            let parsed = try await parseFile(URL(fileURLWithPath: path), source: source)
            cache[path] = ScanFileEntry(source: source,
                                        parserVersion: ScanParserVersions.current(for: source),
                                        mtimeMs: attrs.mtimeMs,
                                        size: attrs.size,
                                        assistant: parsed.assistant,
                                        user: parsed.user,
                                        parentLinks: parsed.parentLinks)
            parsedFiles += 1
            changed = true
        }

        guard changed else {
            PerfLog.log("scan.reconcile.unchanged paths=\(paths.count) unchanged=\(unchangedFiles)")
            return ReconcileCacheUpdate(changed: false, started: started, summary: "unchanged")
        }

        schedulePersist()
        return ReconcileCacheUpdate(
            changed: true,
            started: started,
            summary: "paths=\(paths.count) parsedFiles=\(parsedFiles) removedFiles=\(removedFiles)"
        )
    }

    // MARK: - Snapshot assembly

    private func buildSnapshot(started: Date,
                               claudeDirs: [String],
                               codexDirs: [String]) -> ScanResult {
        PerfLog.measure("snapshot.rebuild") {
            var allAssistant: [AssistantRecord] = []
            var allUser: [UserRecord] = []
            var parentMap: [String: String?] = [:]

            var bySource: [ProviderId: ScanStatsBySource] = [
                .claude: ScanStatsBySource(source: .claude),
                .codex: ScanStatsBySource(source: .codex)
            ]
            bySource[.claude]!.scannedDirs = claudeDirs
            bySource[.codex]!.scannedDirs = codexDirs

            for entry in cache.values {
                allAssistant.append(contentsOf: entry.assistant)
                allUser.append(contentsOf: entry.user)
                for link in entry.parentLinks { parentMap[link.uuid] = link.parentUuid }
                bySource[entry.source]!.filesScanned += 1
                bySource[entry.source]!.assistantRecords += entry.assistant.count
                bySource[entry.source]!.recordsParsed += entry.assistant.count + entry.user.count
            }

            let deduped = PerfLog.measure("snapshot.dedup records=\(allAssistant.count)") {
                dedupAssistantRecords(allAssistant)
            }

            let turnRows = PerfLog.measure("snapshot.turnRows records=\(deduped.count)") {
                Serialize.recordsToTurnRows(records: deduped,
                                            users: allUser,
                                            parentMap: parentMap)
            }

            var stats = ScanStats()
            stats.filesScanned = cache.count
            stats.recordsParsed = allAssistant.count + allUser.count
            stats.assistantRecords = deduped.count
            stats.durationMs = Int(Date().timeIntervalSince(started) * 1000)
            stats.scannedDirs = claudeDirs + codexDirs
            stats.scannedAt = Date()

            return ScanResult(records: deduped,
                              userRecords: allUser,
                              parentMap: parentMap,
                              turnRows: turnRows,
                              stats: stats,
                              bySource: bySource)
        }
    }

    // MARK: - Helpers

    private nonisolated func enumerateJsonl(dirs: [String]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
            let url = URL(fileURLWithPath: dir)
            guard let iterator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .nameKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in iterator {
                let comps = fileURL.pathComponents
                if comps.contains("tool-results") || comps.contains("memory") {
                    iterator.skipDescendants()
                    continue
                }
                let attrs = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .nameKey])
                guard attrs?.isRegularFile == true else { continue }
                let name = attrs?.name ?? fileURL.lastPathComponent
                if name.hasSuffix(".jsonl") {
                    out.append(fileURL)
                }
            }
        }
        return out
    }

    private func normalizedJsonlPaths(_ rawPaths: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in rawPaths {
            let path = normalizePath(raw)
            guard path.hasSuffix(".jsonl") else { continue }
            if seen.insert(path).inserted {
                out.append(path)
            }
        }
        return out
    }

    private func sourceForPath(_ path: String) -> ProviderId? {
        for dir in ClaudeParser.dirs() where isPath(path, under: dir) { return .claude }
        for dir in CodexParser.dirs() where isPath(path, under: dir) { return .codex }
        return nil
    }

    private func providerDirs() -> (claude: [String], codex: [String]) {
        (ClaudeParser.dirs(), CodexParser.dirs())
    }

    private nonisolated static func processJob(_ job: Job, cached: ScanFileEntry?) async throws -> JobResult {
        let path = normalizePath(job.url.path)
        let attrs = try fileAttrs(path)
        if let cached,
           cached.parserVersion == ScanParserVersions.current(for: job.source),
           cached.mtimeMs == attrs.mtimeMs,
           cached.size == attrs.size {
            return JobResult(path: path, entry: cached, reused: true)
        }

        let parsed = try await parseFile(job.url, source: job.source)
        return JobResult(
            path: path,
            entry: ScanFileEntry(source: job.source,
                                 parserVersion: ScanParserVersions.current(for: job.source),
                                 mtimeMs: attrs.mtimeMs,
                                 size: attrs.size,
                                 assistant: parsed.assistant,
                                 user: parsed.user,
                                 parentLinks: parsed.parentLinks),
            reused: false
        )
    }

    private func schedulePersist() {
        let cacheSnapshot = cache
        persistTask?.cancel()
        persistTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            ScanIndexPersistence.save(cache: cacheSnapshot)
        }
    }
}

private struct FileAttrs: Sendable {
    let mtimeMs: Int64
    let size: Int64
}

private func fileAttrs(_ path: String) throws -> FileAttrs {
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    let type = attrs[.type] as? FileAttributeType
    guard type == nil || type == .typeRegular else {
        throw CocoaError(.fileReadUnknown)
    }
    let mtimeMs = Int64((attrs[.modificationDate] as? Date ?? Date()).timeIntervalSince1970 * 1000)
    let size = Int64((attrs[.size] as? NSNumber)?.int64Value ?? 0)
    return FileAttrs(mtimeMs: mtimeMs, size: size)
}

private func parseFile(_ url: URL, source: ProviderId) async throws -> ParsedFile {
    switch source {
    case .claude:
        return try await ClaudeParser.parseFile(url)
    case .codex:
        return try await CodexParser.parseFile(url)
    }
}

private func normalizePath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}

private func isPath(_ path: String, under root: String) -> Bool {
    let normalizedRoot = trimTrailingSlashes(normalizePath(root))
    return path == normalizedRoot || path.hasPrefix(normalizedRoot + "/")
}

private func trimTrailingSlashes(_ path: String) -> String {
    var out = path
    while out.count > 1 && out.hasSuffix("/") {
        out.removeLast()
    }
    return out
}
