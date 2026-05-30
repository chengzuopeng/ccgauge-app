// CodexParserTests.swift — pins down the cumulative→delta token math.
//
// This is the highest-impact test in the suite. The Codex JSONL emits a
// running TOTAL of token usage per token_count event, not the delta for
// that specific call. Earlier ccgauge versions naively summed totals and
// users saw their bill ~2× what it should be. The Swift port has to
// reproduce the forward-only delta math exactly.

import XCTest
@testable import CCGaugeBar

final class CodexParserTests: XCTestCase {

    func fixtureURL(_ name: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"),
            "fixture \(name).jsonl missing"
        )
    }

    // The fixture has THREE token_count events:
    //   1. totals = (input 100, cached 10, output 50, reasoning 5)
    //   2. totals UNCHANGED — should be skipped (refresh / dup event)
    //   3. totals = (input 250, cached 80, output 150, reasoning 20)
    //
    // Expected result: 2 assistant records (not 3, the dup is filtered).
    //
    // Record 1 (first event = treat total as delta):
    //   delta input=100, delta cached=10, delta output=50, delta reasoning=5
    //   record.usage.input = 100 - 10 = 90
    //   record.usage.output = 50 + 5 = 55  (reasoning folded into output per OpenAI billing)
    //   record.usage.cacheRead = 10
    //   record.usage.reasoningTokens = 5
    //
    // Record 2 (third event, deltas vs first event's totals):
    //   delta input = 250-100 = 150, delta cached = 80-10 = 70
    //   delta output = 150-50 = 100, delta reasoning = 20-5 = 15
    //   record.usage.input = 150 - 70 = 80
    //   record.usage.output = 100 + 15 = 115
    //   record.usage.cacheRead = 70
    //   record.usage.reasoningTokens = 15

    func testCodexCumulativeDeltaMath() async throws {
        let url = try fixtureURL("codex-cumulative")
        let parsed = try await CodexParser.parseFile(url)

        XCTAssertEqual(parsed.assistant.count, 2,
                       "duplicate (all-zero delta) token_count event must be skipped")

        let r1 = parsed.assistant[0]
        XCTAssertEqual(r1.usage.inputTokens, 90,
                       "first record: delta input - delta cached = 100 - 10")
        XCTAssertEqual(r1.usage.outputTokens, 55,
                       "first record: delta output + delta reasoning = 50 + 5")
        XCTAssertEqual(r1.usage.cacheReadInputTokens, 10)
        XCTAssertEqual(r1.usage.reasoningTokens, 5)
        XCTAssertEqual(r1.usage.cacheCreationInputTokens, 0,
                       "Codex never reports cache creation tokens")

        let r2 = parsed.assistant[1]
        XCTAssertEqual(r2.usage.inputTokens, 80,
                       "second record: (250-100) - (80-10) = 150 - 70")
        XCTAssertEqual(r2.usage.outputTokens, 115,
                       "second record: (150-50) + (20-5) = 100 + 15")
        XCTAssertEqual(r2.usage.cacheReadInputTokens, 70)
        XCTAssertEqual(r2.usage.reasoningTokens, 15)
    }

    func testCodexMetadataParsesCorrectly() async throws {
        let url = try fixtureURL("codex-cumulative")
        let parsed = try await CodexParser.parseFile(url)
        let r1 = try XCTUnwrap(parsed.assistant.first)

        XCTAssertEqual(r1.source, .codex)
        XCTAssertEqual(r1.model, "gpt-5")
        XCTAssertEqual(r1.cwd, "/Users/me/proj")
        XCTAssertEqual(r1.version, "0.10.0")
        XCTAssertEqual(r1.effort, "medium")
        XCTAssertEqual(r1.sessionId, "sess-1")
    }

    func testCodexUserMessageParsedAsUserRecord() async throws {
        let url = try fixtureURL("codex-cumulative")
        let parsed = try await CodexParser.parseFile(url)

        XCTAssertEqual(parsed.user.count, 1)
        let u = try XCTUnwrap(parsed.user.first)
        XCTAssertEqual(u.textPreview, "hello")
        XCTAssertEqual(u.source, .codex)
        XCTAssertFalse(u.isSynthetic,
                       "real Codex user_message must never be marked synthetic")
    }

    func testCodexAssistantsLinkToTheirUserPrompt() async throws {
        let url = try fixtureURL("codex-cumulative")
        let parsed = try await CodexParser.parseFile(url)
        let userUuid = try XCTUnwrap(parsed.user.first?.uuid)
        for assistant in parsed.assistant {
            XCTAssertEqual(assistant.parentUuid, userUuid,
                           "all assistant records in the same turn must share the user-prompt parent")
        }
    }
}
