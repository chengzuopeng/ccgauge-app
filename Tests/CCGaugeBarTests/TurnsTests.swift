// TurnsTests.swift — buildTurnIndex skips synthetic user records when
// looking for a turn root, so a single human prompt that fans out into
// several tool-use loops + skill-injected user records still collapses
// to ONE turn in the usage table.

import XCTest
@testable import CCGaugeBar

final class TurnsTests: XCTestCase {

    func fixtureURL(_ name: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"),
            "fixture \(name).jsonl missing"
        )
    }

    private func loadParentMap(from parsed: ParsedFile) -> [String: String?] {
        var map: [String: String?] = [:]
        for link in parsed.parentLinks {
            map[link.uuid] = link.parentUuid
        }
        return map
    }

    /// claude-synthetic-user.jsonl has the chain
    ///   sys1 (synthetic) ← sys2 (synthetic) ← u-real ← a1 ← a2
    /// Both assistants must collapse to a SINGLE turn rooted at u-real,
    /// not split into two turns (one per synthetic system-reminder).
    func testTurnIndexSkipsSyntheticUsers() async throws {
        let url = try fixtureURL("claude-synthetic-user")
        let parsed = try await ClaudeParser.parseFile(url)
        let parentMap = loadParentMap(from: parsed)

        let turnIndex = Turns.buildTurnIndex(
            assistants: parsed.assistant,
            users: parsed.user,
            parentMap: parentMap
        )

        XCTAssertEqual(turnIndex["a1"], "u-real",
                       "a1 must root at u-real, NOT sys2 (which is synthetic)")
        XCTAssertEqual(turnIndex["a2"], "u-real",
                       "a2 traverses a1 then u-real, same turn as a1")

        let summaries = Turns.summarize(records: parsed.assistant,
                                        users: parsed.user,
                                        parentMap: parentMap)
        XCTAssertEqual(summaries.count, 1,
                       "fan-out from one human prompt = exactly one turn")
    }

    func testTurnIndexHandlesMissingParent() {
        // An assistant whose parentUuid points nowhere should root at itself
        // rather than infinite-looping or crashing.
        let orphan = AssistantRecord(
            source: .claude,
            uuid: "orphan",
            parentUuid: "ghost-uuid-not-in-map",
            timestamp: Date(),
            timestampIso: "2026-05-20T10:00:00Z",
            sessionId: "s",
            requestId: "r",
            cwd: "/p",
            model: "claude-sonnet-4-5",
            messageId: "m",
            usage: Usage(),
            filePath: "/p/o.jsonl"
        )
        let index = Turns.buildTurnIndex(assistants: [orphan],
                                         users: [],
                                         parentMap: ["orphan": "ghost-uuid-not-in-map"])
        XCTAssertEqual(index["orphan"], "orphan",
                       "no real user-root reachable → record is its own turn")
    }

    func testTurnIndexBreaksParentCycles() {
        // Malformed JSONL could in theory produce A ← B ← A. The 5000-step
        // walk + seen-set must terminate, not hang.
        let a = AssistantRecord(
            source: .claude, uuid: "a", parentUuid: "b",
            timestamp: Date(), timestampIso: "2026-05-20T10:00:00Z",
            sessionId: "s", requestId: "ra", cwd: "/p",
            model: "claude-sonnet-4-5", messageId: "ma",
            usage: Usage(), filePath: "/p/a.jsonl"
        )
        let parentMap: [String: String?] = ["a": "b", "b": "a"]
        let index = Turns.buildTurnIndex(assistants: [a], users: [], parentMap: parentMap)
        XCTAssertEqual(index["a"], "a",
                       "cycle detected, fallback to self as turn root")
    }
}
