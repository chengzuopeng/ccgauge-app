// Serialize.swift — shape AssistantRecord[] into UsageTurnRow[] for the
// usage table.
//
// 1:1 port of ccgauge-refer/lib/serialize.ts#recordsToTurnRows.

import Foundation

public struct UsageCallRow: Sendable, Hashable, Identifiable {
    public let uuid: String
    public let timestamp: Date
    public let timestampIso: String
    public let source: ProviderId
    public let model: String
    public let cwd: String
    public let projectLabel: String
    public let sessionId: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheCreationTokens: Int
    public let reasoningTokens: Int    // Codex display-only
    public let totalTokens: Int
    public let cost: Double
    public let costInput: Double
    public let costOutput: Double
    public let costCacheRead: Double
    public let costCacheWrite: Double  // cacheCreation5m + cacheCreation1h
    public let toolNames: [String]
    public let effort: String?
    /// Nearest user textPreview above this call, walking up parents.
    /// Includes synthetic user records (skill metadata / sub-agent prompts).
    /// Distinct from the turn's `userText`, which is the human prompt.
    public let directPrompt: String?

    public var id: String { uuid }
}

public struct UsageTurnRow: Sendable, Hashable, Identifiable {
    public let turnId: String
    public let timestamp: Date          // earliest child's timestamp
    public let timestampIso: String
    public let endTimestamp: Date       // latest child's timestamp
    public let durationMs: Int
    public let cwd: String
    public let projectLabel: String
    public let sessionId: String
    public let models: [String]         // distinct, in order of first occurrence
    public let callCount: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheCreationTokens: Int
    public let reasoningTokens: Int
    public let totalTokens: Int
    public let cost: Double
    public let costInput: Double
    public let costOutput: Double
    public let costCacheRead: Double
    public let costCacheWrite: Double
    public let toolNames: [String]      // distinct across children
    public let efforts: [String]
    public let userText: String         // turn root UserRecord.textPreview
    public let source: ProviderId       // first child's source (a turn never crosses providers)
    public let children: [UsageCallRow] // sorted asc by timestamp
    /// Pre-lowercased concatenation of every field the usage-page search
    /// box can match against (userText / cwd / sessionId / models / tools).
    /// Computed once when the row is built so each keystroke is a single
    /// O(L) `contains` rather than five `localizedCaseInsensitiveContains`
    /// calls that each lowercase their operand fresh.
    public let searchHaystack: String

    public var id: String { turnId }
}

public enum Serialize {
    public static func recordsToTurnRows(records: [AssistantRecord],
                                         users: [UserRecord],
                                         parentMap: [String: String?]) -> [UsageTurnRow] {
        let turnIndex = Turns.buildTurnIndex(assistants: records, users: users, parentMap: parentMap)

        var userByUuid: [String: UserRecord] = [:]
        userByUuid.reserveCapacity(users.count)
        for u in users { userByUuid[u.uuid] = u }

        // Per-child "directPrompt": walk up parent chain until first user
        // textPreview (synthetic or not). Memoized + back-filled along
        // the way for amortized O(1) on siblings.
        var directPromptCache: [String: String] = [:]
        func resolveDirectPrompt(_ startUuid: String) -> String {
            if let cached = directPromptCache[startUuid] { return cached }
            var path: [String] = []
            var cur: String? = startUuid
            var answer = ""
            var seen = Set<String>()
            while let c = cur, !seen.contains(c) {
                seen.insert(c)
                if let hit = directPromptCache[c] {
                    answer = hit
                    break
                }
                path.append(c)
                if let u = userByUuid[c],
                   !u.textPreview.trimmingCharacters(in: .whitespaces).isEmpty {
                    answer = u.textPreview
                    break
                }
                if let next = parentMap[c] {
                    cur = next
                } else {
                    cur = nil
                }
            }
            for id in path { directPromptCache[id] = answer }
            return answer
        }

        // Group children per turn.
        var groups: [String: [UsageCallRow]] = [:]
        for r in records {
            let turnId = turnIndex[r.uuid] ?? r.uuid
            let c = costOfRecord(r)
            let direct = resolveDirectPrompt(r.uuid)
            let child = UsageCallRow(
                uuid: r.uuid,
                timestamp: r.timestamp,
                timestampIso: r.timestampIso,
                source: r.source,
                model: r.model,
                cwd: r.cwd,
                projectLabel: ProjectLabel.resolve(r.cwd),
                sessionId: r.sessionId,
                inputTokens: r.usage.inputTokens,
                outputTokens: r.usage.outputTokens,
                cacheReadTokens: r.usage.cacheReadInputTokens,
                cacheCreationTokens: r.usage.cacheCreationInputTokens,
                reasoningTokens: r.usage.reasoningTokens ?? 0,
                totalTokens: r.usage.totalTokens,
                cost: c.total,
                costInput: c.input,
                costOutput: c.output,
                costCacheRead: c.cacheRead,
                costCacheWrite: c.cacheCreation5m + c.cacheCreation1h,
                toolNames: r.toolNames,
                effort: r.effort,
                directPrompt: direct.isEmpty ? nil : direct
            )
            groups[turnId, default: []].append(child)
        }

        // Roll up into turn rows.
        var turns: [UsageTurnRow] = []
        turns.reserveCapacity(groups.count)
        for (turnId, childrenUnsorted) in groups {
            // Sort by Date, not by the ISO string — mixed-precision strings
            // (with/without fractional seconds) sort wrong lexically but right
            // chronologically.
            let children = childrenUnsorted.sorted { $0.timestamp < $1.timestamp }
            guard let first = children.first, let last = children.last else { continue }

            var modelsInOrder: [String] = []
            var modelsSeen = Set<String>()
            var toolsInOrder: [String] = []
            var toolsSeen = Set<String>()
            var effortsInOrder: [String] = []
            var effortsSeen = Set<String>()
            var inputTokens = 0, outputTokens = 0
            var cacheReadTokens = 0, cacheCreationTokens = 0
            var reasoningTokens = 0
            var cost = 0.0, costInput = 0.0, costOutput = 0.0
            var costCacheRead = 0.0, costCacheWrite = 0.0

            for c in children {
                if modelsSeen.insert(c.model).inserted { modelsInOrder.append(c.model) }
                for t in c.toolNames where toolsSeen.insert(t).inserted { toolsInOrder.append(t) }
                if let e = c.effort, effortsSeen.insert(e).inserted { effortsInOrder.append(e) }
                inputTokens += c.inputTokens
                outputTokens += c.outputTokens
                cacheReadTokens += c.cacheReadTokens
                cacheCreationTokens += c.cacheCreationTokens
                reasoningTokens += c.reasoningTokens
                cost += c.cost
                costInput += c.costInput
                costOutput += c.costOutput
                costCacheRead += c.costCacheRead
                costCacheWrite += c.costCacheWrite
            }

            let durationMs = max(0, Int(last.timestamp.timeIntervalSince(first.timestamp) * 1000))
            let userRec = userByUuid[turnId]
            let userText = userRec?.textPreview ?? ""

            // Precompute the search haystack — see field doc on UsageTurnRow.
            // Joined with a space so adjacent fields don't yield false hits
            // (e.g. project "foo" + session "barbaz" shouldn't match "obar").
            var haystackParts: [String] = []
            haystackParts.reserveCapacity(5)
            if !userText.isEmpty { haystackParts.append(userText) }
            if !first.cwd.isEmpty { haystackParts.append(first.cwd) }
            if !first.sessionId.isEmpty { haystackParts.append(first.sessionId) }
            haystackParts.append(contentsOf: modelsInOrder)
            haystackParts.append(contentsOf: toolsInOrder)
            let searchHaystack = haystackParts.joined(separator: " ").lowercased()

            turns.append(UsageTurnRow(
                turnId: turnId,
                timestamp: first.timestamp,
                timestampIso: first.timestampIso,
                endTimestamp: last.timestamp,
                durationMs: durationMs,
                cwd: first.cwd,
                projectLabel: ProjectLabel.resolve(first.cwd),
                sessionId: first.sessionId,
                models: modelsInOrder,
                callCount: children.count,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheCreationTokens: cacheCreationTokens,
                reasoningTokens: reasoningTokens,
                totalTokens: inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens,
                cost: cost,
                costInput: costInput,
                costOutput: costOutput,
                costCacheRead: costCacheRead,
                costCacheWrite: costCacheWrite,
                toolNames: toolsInOrder,
                efforts: effortsInOrder,
                userText: userText,
                source: first.source,
                children: children,
                searchHaystack: searchHaystack
            ))
        }

        // Default: newest-started turn first. Compare as Date, not ISO text,
        // because provider logs may mix fractional and non-fractional forms.
        // UsagePage can then reuse this order without sorting on every render.
        turns.sort { $0.timestamp > $1.timestamp }
        return turns
    }
}
