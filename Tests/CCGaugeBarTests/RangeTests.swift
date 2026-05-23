// RangeTests.swift — range → date window, bucket key.

import XCTest
@testable import CCGaugeBar

final class RangeTests: XCTestCase {

    func testRange1DStartsAtMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 14, minute: 30))!
        let r = rangeToDates(.d1, now: now, calendar: cal)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.from!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertNil(r.to)
    }

    func testBucketKey_Hour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let d = cal.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 14))!
        let bk = bucketKey(d, gran: .hour, calendar: cal)
        XCTAssertEqual(bk.key, "2026-05-20T14")
        XCTAssertEqual(bk.label, "05/20 14:00")
    }

    func testBucketKey_Day() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let d = cal.date(from: DateComponents(year: 2026, month: 5, day: 20))!
        let bk = bucketKey(d, gran: .day, calendar: cal)
        XCTAssertEqual(bk.key, "2026-05-20")
        XCTAssertEqual(bk.label, "05/20")
    }

    func testEnumerateBuckets_1D_HasTwentyFour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 14))!
        let buckets = enumerateBuckets(for: .d1, now: now, calendar: cal)
        XCTAssertEqual(buckets.count, 24)
    }

    func testEnumerateBuckets_7D_HasSeven() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 20))!
        let buckets = enumerateBuckets(for: .d7, now: now, calendar: cal)
        XCTAssertEqual(buckets.count, 7)
    }
}
