// Turns.swift — group N AssistantRecords into a single "turn" by walking
// the parent chain to a real (non-synthetic) user prompt.
//
// 1:1 port of ccgauge-refer/lib/turns.ts.
//
// Why this matters: one user prompt fans out into many assistant records
// (tool-use loops, reasoning steps, sub-agents). All of them collapse to
// one "Conversation" row in the usage table. Synthetic user records
// (skill metadata, <system-reminder>, sub-agent first prompts) must be
// skipped or the same human prompt gets split into multiple turns.

import Foundation

public enum Turns {
    /// Defensive cap. Real chains rarely exceed ~50; 5000 protects
    /// against malformed JSONL with cycles or absurd depths.
    public static let maxParentWalk = 5000

    /// Build a `recordUuid → turnRootUuid` index.
    public static func buildTurnIndex(assistants: [AssistantRecord],
                                      users: [UserRecord],
                                      parentMap: [String: String?]) -> [String: String] {
        // 1. Collect the set of uuids that count as "real" turn roots —
        //    user records with non-empty text and not synthetic.
        var userTextSet = Set<String>()
        for u in users where !u.isSynthetic {
            if !u.textPreview.trimmingCharacters(in: .whitespaces).isEmpty {
                userTextSet.insert(u.uuid)
            }
        }

        var result: [String: String] = [:]
        result.reserveCapacity(assistants.count)
        // Memo: any uuid we've already resolved to a turn root. Lets a long
        // tool-loop pay O(depth) once and O(1) for each subsequent sibling.
        var memo: [String: String] = [:]

        func resolve(_ start: String) -> String {
            var path: [String] = []
            var cur: String? = start
            var answer: String?
            var steps = 0
            var seen = Set<String>()

            while let c = cur, steps < maxParentWalk {
                steps += 1
                if seen.contains(c) { break }          // cycle guard
                seen.insert(c)

                if let cached = memo[c] {
                    answer = cached
                    break
                }
                path.append(c)
                if userTextSet.contains(c) {
                    answer = c
                    break
                }
                // `parentMap[c]` is `String??`: outer nil = key missing;
                // inner nil = key present, value null. Either ends the walk.
                if let next = parentMap[c] {
                    cur = next
                } else {
                    cur = nil
                }
            }

            let final = answer ?? start
            // Back-fill the whole path so each ancestor we walked is O(1)
            // on the next call from a sibling.
            for id in path { memo[id] = final }
            return final
        }

        for a in assistants {
            result[a.uuid] = resolve(a.uuid)
        }
        return result
    }

    public struct TurnSummary: Hashable, Sendable {
        public let turnId: String
        public let firstTimestamp: Date
        public let firstTimestampIso: String
        public let firstModel: String
        public let cwd: String
        public let sessionId: String
        public let source: ProviderId

        public init(turnId: String, firstTimestamp: Date, firstTimestampIso: String,
                    firstModel: String, cwd: String, sessionId: String, source: ProviderId) {
            self.turnId = turnId
            self.firstTimestamp = firstTimestamp
            self.firstTimestampIso = firstTimestampIso
            self.firstModel = firstModel
            self.cwd = cwd
            self.sessionId = sessionId
            self.source = source
        }
    }

    /// One TurnSummary per distinct turn root in the input slice. Used by
    /// the Overview KPI ("X 轮对话") and the Trend chart's "active" metric.
    public static func summarize(records: [AssistantRecord],
                                 users: [UserRecord],
                                 parentMap: [String: String?]) -> [String: TurnSummary] {
        let turnIndex = buildTurnIndex(assistants: records, users: users, parentMap: parentMap)
        var out: [String: TurnSummary] = [:]
        for r in records {
            let turnId = turnIndex[r.uuid] ?? r.uuid
            if let existing = out[turnId] {
                // Compare as Date — mixed ISO precision sorts wrong lexically.
                if r.timestamp < existing.firstTimestamp {
                    out[turnId] = TurnSummary(turnId: turnId,
                                              firstTimestamp: r.timestamp,
                                              firstTimestampIso: r.timestampIso,
                                              firstModel: r.model,
                                              cwd: r.cwd,
                                              sessionId: r.sessionId,
                                              source: r.source)
                }
            } else {
                out[turnId] = TurnSummary(turnId: turnId,
                                          firstTimestamp: r.timestamp,
                                          firstTimestampIso: r.timestampIso,
                                          firstModel: r.model,
                                          cwd: r.cwd,
                                          sessionId: r.sessionId,
                                          source: r.source)
            }
        }
        return out
    }
}
