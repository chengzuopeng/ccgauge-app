// FormatTests.swift — every display helper.

import XCTest
@testable import CCGaugeBar

final class FormatTests: XCTestCase {

    func testNum() {
        XCTAssertEqual(Format.num(0), "0")
        XCTAssertEqual(Format.num(999), "999")
        XCTAssertEqual(Format.num(1_000), "1K")
        XCTAssertEqual(Format.num(1_500), "1.5K")
        XCTAssertEqual(Format.num(1_000_000), "1M")
        XCTAssertEqual(Format.num(1_500_000), "1.5M")
    }

    func testTokK() {
        XCTAssertEqual(Format.tokK(999), "999")
        XCTAssertEqual(Format.tokK(1_000), "1K")
        XCTAssertEqual(Format.tokK(1_500), "1.5K")
        XCTAssertEqual(Format.tokK(1_000_000), "1M")
        XCTAssertEqual(Format.tokK(1_250_000), "1.25M")
    }

    func testTokenLocalizedEnglish() {
        XCTAssertEqual(Format.token(999, lang: .en), "999")
        XCTAssertEqual(Format.token(1_000, lang: .en), "1K")
        XCTAssertEqual(Format.token(1_500, lang: .en), "1.5K")
        XCTAssertEqual(Format.token(1_000_000, lang: .en), "1M")
        XCTAssertEqual(Format.token(1_250_000, lang: .en), "1.25M")
    }

    func testTokenLocalizedChinese() {
        XCTAssertEqual(Format.token(9_999, lang: .zh), "9999")
        XCTAssertEqual(Format.token(10_000, lang: .zh), "1万")
        XCTAssertEqual(Format.token(15_000, lang: .zh), "1.5万")
        XCTAssertEqual(Format.token(1_234_567, lang: .zh), "123.5万")
        XCTAssertEqual(Format.token(100_000_000, lang: .zh), "1亿")
        XCTAssertEqual(Format.token(125_000_000, lang: .zh), "1.25亿")
    }

    func testMoney() {
        XCTAssertEqual(Format.money(102.21), "$102.21")
        XCTAssertEqual(Format.money(0), "$0.00")
        XCTAssertEqual(Format.money(1234.5678), "$1,234.57")
    }

    func testMoneyOtherCurrency() {
        XCTAssertEqual(Format.money(10, currency: "CNY"), "¥10.00")
        XCTAssertEqual(Format.money(10, currency: "EUR"), "€10.00")
    }

    func testMoneyTiny() {
        XCTAssertEqual(Format.moneyTiny(0), "$0")
        XCTAssertEqual(Format.moneyTiny(0.000123), "$0.000123")
        XCTAssertEqual(Format.moneyTiny(0.5), "$0.5")
        XCTAssertEqual(Format.moneyTiny(0.012), "$0.012")
        XCTAssertEqual(Format.moneyTiny(1.234567), "$1.23")
    }

    func testMinutes() {
        XCTAssertEqual(Format.minutes(0), "0m")
        XCTAssertEqual(Format.minutes(47), "47m")
        XCTAssertEqual(Format.minutes(60), "1h")
        XCTAssertEqual(Format.minutes(125), "2h 5m")
    }

    func testSeconds() {
        XCTAssertEqual(Format.seconds(45), "45s")
        XCTAssertEqual(Format.seconds(60), "1m")
        XCTAssertEqual(Format.seconds(125), "2m 5s")
    }

    func testPct() {
        XCTAssertEqual(Format.pct(0.5), "<1%")
        XCTAssertEqual(Format.pct(45.4), "45%")
        XCTAssertEqual(Format.pct(45.6), "46%")
    }

    func testShortenModelClaude() {
        XCTAssertEqual(Format.shortenModel("claude-opus-4-7"), "Opus 4.7")
        XCTAssertEqual(Format.shortenModel("claude-sonnet-4-5-20251001"), "Sonnet 4.5")
        XCTAssertEqual(Format.shortenModel("bedrock/claude-haiku-4-5"), "Haiku 4.5")
    }

    func testShortenModelGPT() {
        XCTAssertEqual(Format.shortenModel("gpt-5"), "GPT-5")
        XCTAssertEqual(Format.shortenModel("gpt-5-mini"), "GPT-5 Mini")
        XCTAssertEqual(Format.shortenModel("openai/gpt-5.5-nano"), "GPT-5.5 Nano")
    }

    func testShortenModelOSeries() {
        XCTAssertEqual(Format.shortenModel("o3"), "O3")
        XCTAssertEqual(Format.shortenModel("o4-mini"), "O4-MINI")
    }
}
