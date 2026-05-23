// Dedup.swift — drop duplicate assistant records produced by sub-agent
// forks / worktree mirroring that copy the same JSONL line into multiple
// files.
//
// Primary key: (messageId, requestId). On collision, keep the earliest
// timestamp. Mirrors ccgauge-refer/lib/dedup.ts.
//
// The dedup result drives totals / aggregations, but the **parentMap**
// passed to turn-grouping is kept pre-dedup so chain walks don't break
// when an intermediate hop gets dropped here.

import Foundation

public func dedupAssistantRecords(_ records: [AssistantRecord]) -> [AssistantRecord] {
    var byKey: [String: AssistantRecord] = [:]
    byKey.reserveCapacity(records.count)
    for r in records {
        // messageId + requestId both empty would alias all such records
        // together — but parseAssistant rejects those rows upstream, so the
        // composite key is always meaningful in practice.
        let key = "\(r.messageId)::\(r.requestId)"
        if let existing = byKey[key] {
            // Keep earlier timestamp — closer to "the canonical write" in
            // practice (worktree mirrors copy later). Compare as Date so
            // mixed-precision ISO strings (with/without fractional seconds)
            // still order chronologically.
            if r.timestamp < existing.timestamp {
                byKey[key] = r
            }
        } else {
            byKey[key] = r
        }
    }
    return Array(byKey.values)
}
