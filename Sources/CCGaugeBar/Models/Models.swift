// Models.swift — core domain types for ccgauge-bar.
//
// 1:1 ported from ccgauge-refer/lib/types.ts plus a handful of Swift-side
// conveniences (Date alongside the ISO string so we can keep both fast
// string-key comparisons and proper time arithmetic).

import Foundation

// MARK: - Provider

public enum ProviderId: String, Codable, CaseIterable, Hashable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        }
    }
}

/// What gets stored in `@AppStorage("defaultSource")` and selected in the
/// Source dropdown — adds the `.all` option that `ProviderId` doesn't have.
public enum SourceFilter: String, Codable, CaseIterable, Hashable, Sendable {
    case all
    case claude
    case codex

    public var displayLabel: String {
        displayLabel(lang: .en)
    }

    public func displayLabel(lang: Lang) -> String {
        switch self {
        case .all:    return L10n.t("source.all", lang: lang)
        case .claude: return L10n.t("source.claude", lang: lang)
        case .codex:  return L10n.t("source.codex", lang: lang)
        }
    }
}

// MARK: - Usage / Records

public struct ParentLink: Codable, Hashable, Sendable {
    public let uuid: String
    public let parentUuid: String?

    public init(uuid: String, parentUuid: String?) {
        self.uuid = uuid
        self.parentUuid = parentUuid
    }
}

public struct Usage: Codable, Hashable, Sendable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreationInputTokens: Int = 0
    public var cacheReadInputTokens: Int = 0
    public var cacheCreation5m: Int = 0
    public var cacheCreation1h: Int = 0

    /// Codex only — display-only breakdown that is **already included** in
    /// `outputTokens` and billed at the output rate. Never add this back to
    /// totals or cost.
    public var reasoningTokens: Int?

    public init(inputTokens: Int = 0,
                outputTokens: Int = 0,
                cacheCreationInputTokens: Int = 0,
                cacheReadInputTokens: Int = 0,
                cacheCreation5m: Int = 0,
                cacheCreation1h: Int = 0,
                reasoningTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreation5m = cacheCreation5m
        self.cacheCreation1h = cacheCreation1h
        self.reasoningTokens = reasoningTokens
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }
}

public struct AssistantRecord: Codable, Hashable, Sendable, Identifiable {
    public let source: ProviderId
    public let uuid: String
    public let parentUuid: String?
    public let timestamp: Date
    /// Kept alongside `timestamp` so bucket key generation can use string
    /// comparisons (faster, no DST/timezone surprises).
    public let timestampIso: String
    public let sessionId: String
    public let requestId: String
    public let cwd: String
    public let gitBranch: String?
    public let version: String?
    public let model: String
    public let messageId: String
    public var usage: Usage
    public let toolNames: [String]
    public let hasThinking: Bool
    public let textPreview: String
    /// Codex only: low / medium / high / minimal.
    public let effort: String?
    /// Claude only: sub-agent record (lives under `subagents/agent-*.jsonl`).
    public let isSidechain: Bool
    public let filePath: String

    public var id: String { uuid }

    public init(source: ProviderId, uuid: String, parentUuid: String?,
                timestamp: Date, timestampIso: String,
                sessionId: String, requestId: String,
                cwd: String, gitBranch: String? = nil, version: String? = nil,
                model: String, messageId: String, usage: Usage,
                toolNames: [String] = [], hasThinking: Bool = false,
                textPreview: String = "", effort: String? = nil,
                isSidechain: Bool = false, filePath: String) {
        self.source = source
        self.uuid = uuid
        self.parentUuid = parentUuid
        self.timestamp = timestamp
        self.timestampIso = timestampIso
        self.sessionId = sessionId
        self.requestId = requestId
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.version = version
        self.model = model
        self.messageId = messageId
        self.usage = usage
        self.toolNames = toolNames
        self.hasThinking = hasThinking
        self.textPreview = textPreview
        self.effort = effort
        self.isSidechain = isSidechain
        self.filePath = filePath
    }
}

public struct UserRecord: Codable, Hashable, Sendable, Identifiable {
    public let source: ProviderId
    public let uuid: String
    public let parentUuid: String?
    public let timestamp: Date
    public let timestampIso: String
    public let sessionId: String
    public let cwd: String
    public let textPreview: String
    /// System-injected (skill metadata, <system-reminder>, sub-agent first
    /// prompt). Skipped as turn roots — see `Turns.buildTurnIndex`.
    public let isSynthetic: Bool
    public let isSidechain: Bool
    public let filePath: String

    public var id: String { uuid }

    public init(source: ProviderId, uuid: String, parentUuid: String?,
                timestamp: Date, timestampIso: String,
                sessionId: String, cwd: String, textPreview: String,
                isSynthetic: Bool = false, isSidechain: Bool = false,
                filePath: String) {
        self.source = source
        self.uuid = uuid
        self.parentUuid = parentUuid
        self.timestamp = timestamp
        self.timestampIso = timestampIso
        self.sessionId = sessionId
        self.cwd = cwd
        self.textPreview = textPreview
        self.isSynthetic = isSynthetic
        self.isSidechain = isSidechain
        self.filePath = filePath
    }
}

// MARK: - Scan output

public struct ScanStats: Sendable {
    public var filesScanned: Int = 0
    public var recordsParsed: Int = 0
    public var assistantRecords: Int = 0
    public var durationMs: Int = 0
    public var scannedDirs: [String] = []
    public var scannedAt: Date = .init()

    public init() {}
}

public struct ScanStatsBySource: Sendable {
    public let source: ProviderId
    public var filesScanned: Int = 0
    public var recordsParsed: Int = 0
    public var assistantRecords: Int = 0
    public var scannedDirs: [String] = []

    public init(source: ProviderId) {
        self.source = source
    }
}

/// Output of one full scan. Mirrors `ccgauge-refer/lib/types.ts#ScanResult`
/// plus a precomputed `turnRows` cache so the UI never has to rebuild the
/// turn index per render.
///
/// ⚠️ `parentMap` is the **pre-dedup** uuid → parentUuid map. Turn-grouping
/// walks this chain and would break if intermediate hops got deduped out.
///
/// Note: the wire format is `[String: String?]` — JSON nullable. To keep
/// Sendable inference straightforward (nested Optional<String> in a
/// Dictionary value tripped Swift 5.10's strictness checks), we
/// normalize to `[String: String]` here using a sentinel empty string
/// to represent "explicit nil parent" (= top-level root). Lookups go
/// through `parentUuid(of:)` so callers never see the sentinel.
public struct ScanResult: Sendable {
    public let records: [AssistantRecord]   // already deduped
    public let userRecords: [UserRecord]
    /// Stored as non-Optional values; empty string = "null parent". Use
    /// `parentUuid(of:)` to read.
    private let parentMapStorage: [String: String]
    /// Pre-computed once per scan. Sorted newest-first by start timestamp.
    /// Without this every Overview/Usage view used to call
    /// `Serialize.recordsToTurnRows` per render — a parent-chain walk over
    /// every assistant record (~18k for typical users), 5+ times per render.
    public let turnRows: [UsageTurnRow]
    public let stats: ScanStats
    public let bySource: [ProviderId: ScanStatsBySource]

    public init(records: [AssistantRecord], userRecords: [UserRecord],
                parentMap: [String: String?], turnRows: [UsageTurnRow],
                stats: ScanStats, bySource: [ProviderId: ScanStatsBySource]) {
        self.records = records
        self.userRecords = userRecords
        var storage: [String: String] = [:]
        storage.reserveCapacity(parentMap.count)
        for (k, v) in parentMap {
            storage[k] = v ?? ""
        }
        self.parentMapStorage = storage
        self.turnRows = turnRows
        self.stats = stats
        self.bySource = bySource
    }

    /// Compatibility accessor — rebuilds the original Optional view for code
    /// that takes `[String: String?]` as a parameter (Serialize / Turns).
    /// O(N) copy; called at most once per scan publish.
    public var parentMap: [String: String?] {
        var out: [String: String?] = [:]
        out.reserveCapacity(parentMapStorage.count)
        for (k, v) in parentMapStorage {
            out[k] = v.isEmpty ? .some(nil) : .some(v)
        }
        return out
    }

    /// Direct, allocation-free lookup. Returns `nil` if the uuid is
    /// unknown, `.some(nil)` if known with no parent, `.some(parent)` otherwise.
    public func parentUuid(of uuid: String) -> String?? {
        guard let v = parentMapStorage[uuid] else { return nil }
        return v.isEmpty ? .some(nil) : .some(v)
    }
}

// MARK: - Aggregator output

public struct Totals: Equatable, Sendable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cost: Double = 0
    public var saved: Double = 0
    public var requests: Int = 0

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    public init() {}

    public static let zero = Totals()

    public static func + (lhs: Totals, rhs: Totals) -> Totals {
        var t = Totals()
        t.inputTokens = lhs.inputTokens + rhs.inputTokens
        t.outputTokens = lhs.outputTokens + rhs.outputTokens
        t.cacheReadTokens = lhs.cacheReadTokens + rhs.cacheReadTokens
        t.cacheCreationTokens = lhs.cacheCreationTokens + rhs.cacheCreationTokens
        t.cost = lhs.cost + rhs.cost
        t.saved = lhs.saved + rhs.saved
        t.requests = lhs.requests + rhs.requests
        return t
    }
}

// MARK: - Helpers used across the codebase

/// Decode an ISO8601 string (with or without fractional seconds) into a Date.
/// Falls back to `Date()` if parsing fails — never crashes, mirrors
/// parse-jsonl.ts's behaviour.
///
/// Uses `Date.ISO8601FormatStyle` (value type, `Sendable`) rather than the
/// reference-typed `ISO8601DateFormatter` whose thread safety isn't
/// documented. We hit this from concurrent TaskGroup parsers.
public enum IsoDate {
    private static let withFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    public static func parse(_ s: String) -> Date {
        if let d = try? withFractional.parse(s) { return d }
        if let d = try? withoutFractional.parse(s) { return d }
        return Date()
    }

    public static func format(_ d: Date) -> String {
        withFractional.format(d)
    }
}
