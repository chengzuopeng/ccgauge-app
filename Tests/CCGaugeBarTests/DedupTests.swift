// DedupTests.swift — verify (messageId, requestId) primary-key dedup
// keeps the earlier-timestamp record when worktree mirrors duplicate
// the same JSONL line into multiple files.

import XCTest
@testable import CCGaugeBar

final class DedupTests: XCTestCase {

    private func record(uuid: String,
                        messageId: String,
                        requestId: String,
                        timestampIso: String) -> AssistantRecord {
        AssistantRecord(
            source: .claude,
            uuid: uuid,
            parentUuid: nil,
            timestamp: IsoDate.parse(timestampIso),
            timestampIso: timestampIso,
            sessionId: "s",
            requestId: requestId,
            cwd: "/p",
            model: "claude-sonnet-4-5",
            messageId: messageId,
            usage: Usage(inputTokens: 10),
            filePath: "/p/\(uuid).jsonl"
        )
    }

    func testKeepsEarlierTimestampOnCollision() {
        let earlier = record(uuid: "u-early",
                             messageId: "msg-1",
                             requestId: "req-1",
                             timestampIso: "2026-05-20T10:00:00.000Z")
        let later = record(uuid: "u-late",
                           messageId: "msg-1",
                           requestId: "req-1",
                           timestampIso: "2026-05-20T10:05:00.000Z")

        let deduped = dedupAssistantRecords([later, earlier])

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.uuid, "u-early",
                       "earlier timestamp survives — worktree mirror copies the same record later")
    }

    func testDistinctKeysSurvive() {
        let a = record(uuid: "a",
                       messageId: "msg-1",
                       requestId: "req-1",
                       timestampIso: "2026-05-20T10:00:00.000Z")
        let b = record(uuid: "b",
                       messageId: "msg-2",         // different messageId
                       requestId: "req-1",
                       timestampIso: "2026-05-20T10:00:01.000Z")
        let c = record(uuid: "c",
                       messageId: "msg-1",
                       requestId: "req-2",         // different requestId
                       timestampIso: "2026-05-20T10:00:02.000Z")

        let deduped = dedupAssistantRecords([a, b, c])
        XCTAssertEqual(Set(deduped.map { $0.uuid }), Set(["a", "b", "c"]))
    }

    func testEmptyInput() {
        XCTAssertEqual(dedupAssistantRecords([]).count, 0)
    }

    func testHandlesMixedPrecisionTimestamps() {
        // Same key, two records — one with fractional seconds, one without.
        // Comparing as String would mis-order ("10:00:00" < "10:00:00.500"
        // happens to work, but cases like ":00.500" vs ":01" can flip).
        // We sort by Date so this is robust.
        let withFractional = record(uuid: "frac",
                                    messageId: "msg-1",
                                    requestId: "req-1",
                                    timestampIso: "2026-05-20T10:00:00.500Z")
        let withoutFractional = record(uuid: "plain",
                                       messageId: "msg-1",
                                       requestId: "req-1",
                                       timestampIso: "2026-05-20T10:00:01Z")

        let deduped = dedupAssistantRecords([withoutFractional, withFractional])
        XCTAssertEqual(deduped.first?.uuid, "frac",
                       "fractional-seconds timestamp is 500ms EARLIER than the next-second one")
    }
}
