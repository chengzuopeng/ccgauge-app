// PricingTests.swift — smoke tests for pricing resolution and cost math.

import XCTest
@testable import CCGaugeBar

final class PricingTests: XCTestCase {

    func testExactClaudeMatch() {
        let p = resolveClaudePricing("claude-opus-4-7")
        XCTAssertEqual(p?.input, 5)
        XCTAssertEqual(p?.output, 25)
        XCTAssertEqual(p?.cacheRead, 0.5)
    }

    func testClaudeDateStripped() {
        let p = resolveClaudePricing("claude-sonnet-4-6-20251001")
        XCTAssertEqual(p?.input, 3)
    }

    func testClaudePrefixStripped() {
        let p = resolveClaudePricing("bedrock/claude-haiku-4-5")
        XCTAssertEqual(p?.input, 1)
    }

    func testClaudeFamilyFallback() {
        let p = resolveClaudePricing("claude-opus-experimental-v99")
        // contains "opus" → opus 4-7 fallback rates
        XCTAssertEqual(p?.input, 5)
    }

    func testCodexExact() {
        let p = resolveCodexPricing("gpt-5-mini")
        XCTAssertEqual(p?.input, 0.25)
    }

    func testCodexOFamilyFallback() {
        let p = resolveCodexPricing("o42-experimental")
        // ^o\d → o3 rates
        XCTAssertEqual(p?.input, 2)
    }

    func testCostFromUsage_NoPricing_ReturnsZero() {
        let u = Usage(inputTokens: 1000, outputTokens: 1000)
        let c = costFromUsage(u, pricing: nil)
        XCTAssertEqual(c.total, 0)
        XCTAssertEqual(c.saved, 0)
    }

    func testCostFromUsage_Basic() {
        // 1M input tokens × $5/M = $5
        // 1M output tokens × $25/M = $25
        // total = $30; saved = 0 (no cache reads)
        let u = Usage(inputTokens: 1_000_000, outputTokens: 1_000_000)
        let c = costFromUsage(u, pricing: ClaudePricing.table["claude-opus-4-7"])
        XCTAssertEqual(c.total, 30, accuracy: 0.001)
        XCTAssertEqual(c.saved, 0)
    }

    func testCostFromUsage_CacheSaved() {
        // 1M cacheRead tokens at opus-4-7: 0.5/M cost, but would have been 5/M
        // → saved = 4.5
        let u = Usage(cacheReadInputTokens: 1_000_000)
        let c = costFromUsage(u, pricing: ClaudePricing.table["claude-opus-4-7"])
        XCTAssertEqual(c.cacheRead, 0.5, accuracy: 0.001)
        XCTAssertEqual(c.saved, 4.5, accuracy: 0.001)
    }
}
