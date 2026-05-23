// Aggregator.swift — value types for time-bucketed / per-model / per-project
// rollups consumed by the Overview page.
//
// History: this file used to also export `aggregateTotals`, `aggregateByTime`,
// `aggregateByModel`, `aggregateByProject` standalone functions, but all view
// paths now go through `PopoverViewModel.buildOverviewData` which performs a
// single-pass aggregation over `recordsInWindow`. The standalone functions
// were unreachable and were deleted to keep the surface small. If you need
// them back (e.g. for a new test), add the call site first.

import Foundation

// MARK: - Time bucketing

public struct TimeBucket: Sendable {
    public let key: String
    public let label: String
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cost: Double = 0
    public var saved: Double = 0
    public var requests: Int = 0
    /// Per-source token total (for the All view's split-stacked bar).
    public var claudeTokens: Int = 0
    public var codexTokens: Int = 0
    /// Filled in after summarizeTurns runs against the same time slice.
    public var turns: Int = 0

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    public init(key: String, label: String) {
        self.key = key
        self.label = label
    }
}

// MARK: - By Model

public struct ModelAgg: Sendable, Hashable {
    public let model: String           // raw model name
    public let source: ProviderId
    public var requests: Int = 0
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cost: Double = 0
    public var saved: Double = 0

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    public init(model: String, source: ProviderId) {
        self.model = model
        self.source = source
    }
}

// MARK: - By Project (cwd)

public struct ProjectAgg: Sendable, Hashable {
    public let cwd: String
    public let source: ProviderId
    public var projectName: String     // basename(cwd)
    public var projectLabel: String    // worktree-aware
    public var requests: Int = 0
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cost: Double = 0
    public var saved: Double = 0

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    public init(cwd: String, source: ProviderId) {
        self.cwd = cwd
        self.source = source
        self.projectName = ProjectLabel.projectNameFromCwd(cwd)
        self.projectLabel = ProjectLabel.resolve(cwd)
    }
}
