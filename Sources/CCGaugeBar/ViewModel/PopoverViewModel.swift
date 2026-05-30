// PopoverViewModel.swift — derives all view-data from ScanStore + user prefs.
//
// One source of truth for source / range / metric / sortMode / page.
// Persisted prefs go through `@AppStorage` so they survive popover toggles
// and app relaunches.

import Foundation
import SwiftUI
import Combine

public enum PageId: String, Codable {
    case overview
    case usage
}

public enum TrendMetric: String, Codable {
    case tokens
    case cost
    case active
}

public enum SortMode: String, Codable {
    case cost
    case token
}

struct OverviewData {
    let totals: Totals
    let turnCount: Int
    let trendBars: [TrendBarVM]
    let projectItems: [DistItem]
    let modelItems: [DistItem]
}

struct UsageRowsData {
    let baseCount: Int
    let filteredCount: Int
    let rows: [UsageTurnRow]
}

@MainActor
public final class PopoverViewModel: ObservableObject {

    // MARK: - persistent prefs (UserDefaults via @AppStorage)

    @AppStorage("page") public var page: PageId = .overview
    @AppStorage("source") public var source: SourceFilter = .all
    @AppStorage("range") public var range: Range = .d1
    @AppStorage("trendMetric") public var metric: TrendMetric = .tokens
    @AppStorage("defaultSort") public var sortMode: SortMode = .cost
    @AppStorage("demoMode") public var demoMode: Bool = false
    @AppStorage("currency") public var currency: String = "USD"
    @AppStorage("lang") public var lang: Lang = .system

    // MARK: - derived (ScanStore is published; SwiftUI re-renders)

    public let scanStore: ScanStore
    private var defaultsObserver: AnyCancellable?

    public init(scanStore: ScanStore) {
        self.scanStore = scanStore
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }
    }

    // MARK: - Source / Range UX helpers

    /// Click rules for ProviderCard (re-click selected card collapses to .all).
    public func toggleProvider(_ p: ProviderId) {
        switch source {
        case .all:
            source = (p == .claude) ? .claude : .codex
        case .claude:
            source = (p == .claude) ? .all : .codex
        case .codex:
            source = (p == .codex) ? .all : .claude
        }
    }

    // MARK: - Time window

    /// `Range` used on the Usage page (which has the extra `ALL` option).
    /// On the Overview page we cap to whatever range is set; Overview never
    /// reaches `.all`.
    public var effectiveOverviewRange: Range {
        page == .overview && range == .all ? .d30 : range
    }

    public var effectiveUsageRange: Range { range }

    private var activeWindowRange: Range {
        page == .overview ? effectiveOverviewRange : effectiveUsageRange
    }

    public var dateWindow: DateRange {
        rangeToDates(activeWindowRange)
    }

    // MARK: - Localized formatter

    public func t(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, lang: lang)
            .replacingFormatArgs(args)
    }

    // MARK: - Cached scan derivations
    //
    // 5+ views each access these per render, so we memoize the filter
    // result keyed by `(scan generation, source, range)`. Otherwise we
    // re-filter 18k records four times per render, which is the second-
    // tier perf problem after the (already-fixed) turn-row caching:
    //
    //   ProviderRow:  providerStats × 2
    //   KpiGrid:      recordsInWindow + turnsInWindow
    //   TrendChart:   recordsInWindow + turnsInWindow
    //   DistRow:      recordsInWindow × 2
    //   PopoverShell: hasRecordsInWindow
    //
    // First access per (key) hits the slow path (~5–10 ms). Every other
    // access in the same render frame is O(1).

    public var allTurnRows: [UsageTurnRow] {
        scanStore.scan?.turnRows ?? []
    }

    public var allRecords: [AssistantRecord] {
        scanStore.scan?.records ?? []
    }

    /// Cache key: scan timestamp + source + range. Any of those changing
    /// → invalidate. Using `Date?` as the scan generation key is fine
    /// because `ScanStore.performScan` sets `stats.scannedAt = Date()`
    /// on every fresh scan; equality discriminates new vs. reused scans.
    private struct WindowSnapshot {
        let scanKey: Date?
        let source: SourceFilter
        let range: Range
        let records: [AssistantRecord]
        let turnRows: [UsageTurnRow]
    }

    private struct HasRecordsCache {
        let scanKey: Date?
        let source: SourceFilter
        let range: Range
        let hasRecords: Bool
    }

    /// Multi-entry cache keyed by `(scanKey, source, range)` so flipping
    /// between Overview (.d30) and Usage (.all) doesn't kick each other's
    /// snapshot out. We bound it: drop entries for stale scans and keep
    /// at most 4 entries per scan generation (one per range × current source).
    private var _windowCache: [WindowKey: WindowSnapshot] = [:]
    private var _hasRecordsCache: HasRecordsCache?

    private struct WindowKey: Hashable {
        let scanKey: Date?
        let source: SourceFilter
        let range: Range
    }

    private func windowSnapshot() -> WindowSnapshot {
        windowSnapshot(range: activeWindowRange)
    }

    private func windowSnapshot(range activeRange: Range) -> WindowSnapshot {
        let scan = scanStore.scan
        let scanKey = scan?.stats.scannedAt
        let key = WindowKey(scanKey: scanKey, source: source, range: activeRange)
        if let snap = _windowCache[key] {
            return snap
        }

        // New scan? Drop everything from old scans before adding the new entry.
        evictStaleWindowCache(currentScanKey: scanKey)

        let started = CFAbsoluteTimeGetCurrent()
        let dates = rangeToDates(activeRange)
        let allRecs = scan?.records ?? []
        let allTurns = scan?.turnRows ?? []
        let records = allRecs.filter { rec in
            if source != .all, rec.source.rawValue != source.rawValue { return false }
            if let f = dates.from, rec.timestamp < f { return false }
            if let t = dates.to,   rec.timestamp > t { return false }
            return true
        }
        let turns = allTurns.filter { row in
            if source != .all, row.source.rawValue != source.rawValue { return false }
            if let f = dates.from, row.timestamp < f { return false }
            if let t = dates.to,   row.timestamp > t { return false }
            return true
        }
        let snap = WindowSnapshot(scanKey: scanKey, source: source, range: activeRange,
                                  records: records, turnRows: turns)
        _windowCache[key] = snap
        let dt = (CFAbsoluteTimeGetCurrent() - started) * 1000
        PerfLog.log("window.recompute source=\(source.rawValue) range=\(activeRange.rawValue) recs=\(records.count)/\(allRecs.count) turns=\(turns.count)/\(allTurns.count) \(String(format: "%.1f", dt))ms")
        return snap
    }

    private func evictStaleWindowCache(currentScanKey: Date?) {
        _windowCache = _windowCache.filter { $0.key.scanKey == currentScanKey }
    }

    /// Records narrowed to the current source × range. Backed by `_windowSnap`.
    public var recordsInWindow: [AssistantRecord] { windowSnapshot().records }

    /// Turn rows narrowed to the current source × range. Backed by `_windowSnap`.
    public var turnsInWindow: [UsageTurnRow] { windowSnapshot().turnRows }

    public var hasRecordsInWindow: Bool {
        let scan = scanStore.scan
        let scanKey = scan?.stats.scannedAt
        let activeRange = activeWindowRange
        if let cache = _hasRecordsCache,
           cache.scanKey == scanKey,
           cache.source == source,
           cache.range == activeRange {
            return cache.hasRecords
        }

        let dates = rangeToDates(activeRange)
        let hasRecords = (scan?.records ?? []).contains { rec in
            if source != .all, rec.source.rawValue != source.rawValue { return false }
            if let f = dates.from, rec.timestamp < f { return false }
            if let t = dates.to, rec.timestamp > t { return false }
            return true
        }
        _hasRecordsCache = HasRecordsCache(scanKey: scanKey,
                                           source: source,
                                           range: activeRange,
                                           hasRecords: hasRecords)
        return hasRecords
    }

    /// Provider Card stats — turn count + active minutes per provider.
    /// Cache key is `(scanKey, range)` ONLY (NOT source) because both
    /// cards are always shown regardless of the user's source pick.
    private struct ProviderStatsCache {
        let scanKey: Date?
        let range: Range
        let claude: (turns: Int, minutes: Int)
        let codex: (turns: Int, minutes: Int)
    }
    private var _providerCache: ProviderStatsCache?

    public func providerStats(_ p: ProviderId) -> (turns: Int, minutes: Int) {
        let scanKey = scanStore.scan?.stats.scannedAt
        let activeRange = activeWindowRange
        if let c = _providerCache, c.scanKey == scanKey, c.range == activeRange {
            return p == .claude ? c.claude : c.codex
        }
        let dates = dateWindow
        var claudeTurns = 0, claudeMs = 0
        var codexTurns = 0, codexMs = 0
        for row in allTurnRows {
            if let f = dates.from, row.timestamp < f { continue }
            if let t = dates.to,   row.timestamp > t { continue }
            switch row.source {
            case .claude: claudeTurns += 1; claudeMs += row.durationMs
            case .codex:  codexTurns += 1;  codexMs += row.durationMs
            }
        }
        let snap = ProviderStatsCache(
            scanKey: scanKey, range: activeRange,
            claude: (claudeTurns, claudeMs / 60_000),
            codex:  (codexTurns,  codexMs  / 60_000)
        )
        _providerCache = snap
        return p == .claude ? snap.claude : snap.codex
    }

    // MARK: - Overview snapshot

    private struct OverviewDataCache {
        let scanKey: Date?
        let source: SourceFilter
        let range: Range
        let sortMode: SortMode
        let demoMode: Bool
        let lang: Lang
        let data: OverviewData
    }

    private var _overviewDataCache: OverviewDataCache?

    func overviewData() -> OverviewData {
        let scanKey = scanStore.scan?.stats.scannedAt
        let activeRange = effectiveOverviewRange
        if let cache = _overviewDataCache,
           cache.scanKey == scanKey,
           cache.source == source,
           cache.range == activeRange,
           cache.sortMode == sortMode,
           cache.demoMode == demoMode,
           cache.lang == lang {
            return cache.data
        }

        let data = PerfLog.measure("overview.snapshot source=\(source.rawValue) range=\(activeRange.rawValue) sort=\(sortMode.rawValue)") {
            buildOverviewData(range: activeRange)
        }
        _overviewDataCache = OverviewDataCache(
            scanKey: scanKey,
            source: source,
            range: activeRange,
            sortMode: sortMode,
            demoMode: demoMode,
            lang: lang,
            data: data
        )
        return data
    }

    private func buildOverviewData(range activeRange: Range) -> OverviewData {
        let snap = windowSnapshot(range: activeRange)
        let records = snap.records
        let turns = snap.turnRows
        let gran = granularityFor(activeRange)

        var totals = Totals()
        var buckets: [String: TimeBucket] = [:]
        var projects: [String: ProjectAgg] = [:]
        var models: [String: ModelAgg] = [:]

        for r in records {
            let cost = costOfRecord(r)
            totals.inputTokens += r.usage.inputTokens
            totals.outputTokens += r.usage.outputTokens
            totals.cacheReadTokens += r.usage.cacheReadInputTokens
            totals.cacheCreationTokens += r.usage.cacheCreationInputTokens
            totals.cost += cost.total
            totals.saved += cost.saved
            totals.requests += 1

            let bucketKeyValue = bucketKey(r.timestamp, gran: gran)
            var bucket = buckets[bucketKeyValue.key] ?? TimeBucket(key: bucketKeyValue.key,
                                                                    label: bucketKeyValue.label)
            bucket.inputTokens += r.usage.inputTokens
            bucket.outputTokens += r.usage.outputTokens
            bucket.cacheReadTokens += r.usage.cacheReadInputTokens
            bucket.cacheCreationTokens += r.usage.cacheCreationInputTokens
            bucket.cost += cost.total
            bucket.saved += cost.saved
            bucket.requests += 1
            switch r.source {
            case .claude: bucket.claudeTokens += r.usage.totalTokens
            case .codex: bucket.codexTokens += r.usage.totalTokens
            }
            buckets[bucketKeyValue.key] = bucket

            let cwd = r.cwd.isEmpty ? "(unknown)" : r.cwd
            let projectKey = "\(r.source.rawValue)::\(cwd)"
            var project = projects[projectKey] ?? ProjectAgg(cwd: cwd, source: r.source)
            project.requests += 1
            project.inputTokens += r.usage.inputTokens
            project.outputTokens += r.usage.outputTokens
            project.cacheReadTokens += r.usage.cacheReadInputTokens
            project.cacheCreationTokens += r.usage.cacheCreationInputTokens
            project.cost += cost.total
            project.saved += cost.saved
            projects[projectKey] = project

            let modelKey = "\(r.source.rawValue)::\(r.model)"
            var model = models[modelKey] ?? ModelAgg(model: r.model, source: r.source)
            model.requests += 1
            model.inputTokens += r.usage.inputTokens
            model.outputTokens += r.usage.outputTokens
            model.cacheReadTokens += r.usage.cacheReadInputTokens
            model.cacheCreationTokens += r.usage.cacheCreationInputTokens
            model.cost += cost.total
            model.saved += cost.saved
            models[modelKey] = model
        }

        var turnsByKey: [String: Int] = [:]
        for row in turns {
            let key = bucketKey(row.timestamp, gran: gran).key
            turnsByKey[key, default: 0] += 1
        }

        let trendBars = enumerateBuckets(for: activeRange).map { key, label, _ in
            let bucket = buckets[key]
            return TrendBarVM(label: label,
                              claude: bucket?.claudeTokens ?? 0,
                              codex: bucket?.codexTokens ?? 0,
                              cost: bucket?.cost ?? 0,
                              active: turnsByKey[key] ?? 0)
        }
        let projectItems = buildProjectItems(aggs: Array(projects.values))
        let modelItems = buildModelItems(aggs: Array(models.values))

        return OverviewData(
            totals: totals,
            turnCount: turns.count,
            trendBars: trendBars,
            projectItems: projectItems,
            modelItems: modelItems
        )
    }

    private func buildProjectItems(aggs: [ProjectAgg]) -> [DistItem] {
        let sorted = aggs.sorted { lhs, rhs in
            sortMode == .cost ? lhs.cost > rhs.cost : lhs.totalTokens > rhs.totalTokens
        }
        let top = Array(sorted.prefix(5))
        let rest = sorted.dropFirst(5)

        var items = top.enumerated().map { idx, project in
            let label = demoMode
                ? t("dist.demo_project").replacingOccurrences(of: "%d", with: "\(idx + 1)")
                : project.projectLabel
            return DistItem(id: "p\(idx)",
                            label: label,
                            cost: project.cost,
                            tokens: project.totalTokens,
                            source: project.source.rawValue)
        }

        if !rest.isEmpty {
            let restCost = rest.reduce(0) { $0 + $1.cost }
            let restTokens = rest.reduce(0) { $0 + $1.totalTokens }
            items.append(DistItem(id: "other",
                                  label: t("dist.other"),
                                  cost: restCost,
                                  tokens: restTokens,
                                  source: "other"))
        }
        return items
    }

    private func buildModelItems(aggs: [ModelAgg]) -> [DistItem] {
        let sorted = aggs.sorted { lhs, rhs in
            sortMode == .cost ? lhs.cost > rhs.cost : lhs.totalTokens > rhs.totalTokens
        }
        let top = Array(sorted.prefix(5))
        let rest = sorted.dropFirst(5)

        var items = top.enumerated().map { idx, model in
            DistItem(id: "m\(idx)",
                     label: Format.shortenModel(model.model),
                     cost: model.cost,
                     tokens: model.totalTokens,
                     source: model.source.rawValue)
        }

        if !rest.isEmpty {
            let restCost = rest.reduce(0) { $0 + $1.cost }
            let restTokens = rest.reduce(0) { $0 + $1.totalTokens }
            items.append(DistItem(id: "other",
                                  label: t("dist.other"),
                                  cost: restCost,
                                  tokens: restTokens,
                                  source: "other"))
        }
        return items
    }

    // MARK: - Usage rows snapshot

    private struct UsageRowsCache {
        let scanKey: Date?
        let source: SourceFilter
        let range: Range
        let query: String
        let sortAsc: Bool
        let data: UsageRowsData
    }

    private var _usageRowsCache: UsageRowsCache?

    func usageRows(query rawQuery: String, sortAsc: Bool) -> UsageRowsData {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanKey = scanStore.scan?.stats.scannedAt
        let activeRange = effectiveUsageRange
        if let cache = _usageRowsCache,
           cache.scanKey == scanKey,
           cache.source == source,
           cache.range == activeRange,
           cache.query == query,
           cache.sortAsc == sortAsc {
            return cache.data
        }

        let data = PerfLog.measure("usage.rows source=\(source.rawValue) range=\(activeRange.rawValue) query=\(query.isEmpty ? "0" : "1") sortAsc=\(sortAsc)") {
            buildUsageRows(query: query, range: activeRange, sortAsc: sortAsc)
        }
        _usageRowsCache = UsageRowsCache(
            scanKey: scanKey,
            source: source,
            range: activeRange,
            query: query,
            sortAsc: sortAsc,
            data: data
        )
        return data
    }

    private func buildUsageRows(query: String, range activeRange: Range, sortAsc: Bool) -> UsageRowsData {
        let base = windowSnapshot(range: activeRange).turnRows

        let searched: [UsageTurnRow]
        if query.isEmpty {
            searched = base
        } else {
            // Single O(L) substring search against the pre-lowercased haystack
            // built when the row was constructed. Previously this filtered
            // five Strings per row with localizedCaseInsensitiveContains,
            // which lowercases its operand on every keystroke.
            let needle = query.lowercased()
            searched = base.filter { $0.searchHaystack.contains(needle) }
        }

        let rows = sortAsc ? Array(searched.reversed()) : searched
        return UsageRowsData(baseCount: base.count,
                             filteredCount: searched.count,
                             rows: rows)
    }

    // MARK: - Provider configured (cached per-process; rarely changes)

    /// Whether the provider has at least one of its data dirs on disk.
    /// Cached at first access — recompute requires app restart, which is
    /// acceptable (installing/removing Claude or Codex mid-session is rare).
    private lazy var _configuredCache: [ProviderId: Bool] = {
        var m: [ProviderId: Bool] = [:]
        let fm = FileManager.default
        for p in ProviderId.allCases {
            let dirs: [String] = (p == .claude) ? ClaudeParser.dirs() : CodexParser.dirs()
            m[p] = dirs.contains { dir in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue
            }
        }
        return m
    }()

    public func providerConfigured(_ p: ProviderId) -> Bool {
        _configuredCache[p] ?? false
    }
}

// MARK: - SourceFilter / Range / SortMode AppStorage adapters
//
// @AppStorage needs RawRepresentable — and our String-rawValue enums
// already conform via Codable's String backing, but @AppStorage requires
// the rawValue to be a UserDefaults-compatible scalar. Adding RawRepresentable
// conformance is implicit because rawValue == String already.

// MARK: - %@ → args substitution helper

extension String {
    /// Minimal printf-style substitution. We use `%@` placeholders to keep
    /// the i18n keys readable; Swift's String(format:) wants `%@` for Obj-C
    /// objects (which Strings are when bridged) — so we manually replace.
    func replacingFormatArgs(_ args: [CVarArg]) -> String {
        var out = self
        for arg in args {
            // Try %@ first (string-shaped placeholders).
            if let r = out.range(of: "%@") {
                out.replaceSubrange(r, with: "\(arg)")
                continue
            }
            // Then %d for ints we pass deliberately.
            if let r = out.range(of: "%d") {
                out.replaceSubrange(r, with: "\(arg)")
            }
        }
        return out
    }
}
