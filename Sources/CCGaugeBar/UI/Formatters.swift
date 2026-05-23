// Formatters.swift — every "how do I display this number" helper.
//
// Mirrors the JS helpers in ccgauge-app-design/project/data.jsx and
// ccgauge-refer/lib/utils.ts.

import Foundation

public enum Format {
    private static let formatterLock = NSLock()
    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var shortenCache: [String: String] = [:]

    private static let modelPrefixRegex = try! NSRegularExpression(pattern: #"^(vertex_ai|bedrock|anthropic|openai)/"#)
    private static let oSeriesRegex = try! NSRegularExpression(pattern: #"^o\d"#)
    private static let dateSuffixRegex = try! NSRegularExpression(pattern: #"-\d{8}$"#)
    private static let claudePrefixRegex = try! NSRegularExpression(pattern: #"^claude-"#)

    // MARK: - Numbers

    /// fmtNum: `<1000 → raw` · `<1M → x.xK` · `≥1M → x.xM`. Strips trailing `.0`.
    public static func num(_ n: Int) -> String {
        if n < 1_000 { return "\(n)" }
        if n < 1_000_000 {
            let v = Double(n) / 1_000
            return trim(String(format: "%.1f", v)) + "K"
        }
        let v = Double(n) / 1_000_000
        return trim(String(format: "%.1f", v)) + "M"
    }

    /// tokK: same family as `num`, but uses 2 decimals for M and matches the
    /// usage table's exact spec.
    public static func tokK(_ n: Int) -> String {
        token(n, lang: .en)
    }

    public static func token(_ n: Int, lang: Lang) -> String {
        if L10n.resolve(lang) == .zh {
            return tokenZh(n)
        }
        if n < 1_000 { return "\(n)" }
        if n < 1_000_000 {
            return trim(String(format: "%.1f", Double(n) / 1_000)) + "K"
        }
        let v = Double(n) / 1_000_000
        return trim(String(format: "%.2f", v), suffix: ".00") + "M"
    }

    private static func tokenZh(_ n: Int) -> String {
        if n < 10_000 { return "\(n)" }
        if n < 100_000_000 {
            let v = Double(n) / 10_000
            return trim(String(format: "%.1f", v)) + "万"
        }
        let v = Double(n) / 100_000_000
        return trim(String(format: "%.2f", v), suffix: ".00") + "亿"
    }

    /// fmtMoney(n, currency): `$X,XXX.XX` style.
    /// Note: currency symbol is swapped per the design; **no exchange-rate
    /// conversion happens.** Numbers remain USD equivalent.
    public static func money(_ n: Double, currency: String = "USD") -> String {
        let symbol = currencySymbols[currency] ?? "$"
        formatterLock.lock()
        let body = moneyFormatter.string(from: NSNumber(value: n)) ?? "0.00"
        formatterLock.unlock()
        return "\(symbol)\(body)"
    }

    /// fmtMoneyTiny: render very small amounts with extra decimals so
    /// per-call costs don't collapse to "$0".
    public static func moneyTiny(_ n: Double) -> String {
        if n == 0 { return "$0" }
        if abs(n) < 0.01 {
            return "$" + stripTrailingZeros(String(format: "%.6f", n))
        }
        if abs(n) < 1 {
            return "$" + stripTrailingZeros(String(format: "%.3f", n))
        }
        return String(format: "$%.2f", n)
    }

    /// Strip ALL trailing zeros (and a hanging trailing dot) from a
    /// decimal numeral. Mirrors JS `.replace(/0+$/, '').replace(/\.$/, '')`.
    /// Examples: "0.500" → "0.5", "0.000123" → "0.000123", "1.000" → "1".
    private static func stripTrailingZeros(_ s: String) -> String {
        // Only meaningful if there's a decimal point — leave integers alone.
        guard s.contains(".") else { return s }
        var out = s
        while out.hasSuffix("0") { out.removeLast() }
        if out.hasSuffix(".") { out.removeLast() }
        return out
    }

    // MARK: - Time

    /// fmtMinutes: `0m / Xm / Xh / Xh Ym`.
    public static func minutes(_ m: Int) -> String {
        if m <= 0 { return "0m" }
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }

    /// fmtSeconds for the "耗时" cell on the expanded usage row.
    public static func seconds(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m \(r)s"
    }

    /// Percent: pct < 1 → "<1%"; otherwise rounded "X%".
    public static func pct(_ p: Double) -> String {
        if p < 1 { return "<1%" }
        return "\(Int(p.rounded()))%"
    }

    // MARK: - Date / clock display

    /// "HH:mm" (24h, local timezone).
    public static func hhmm(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// "HH:mm:ss" (24h, local).
    public static func hhmmss(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: d)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// "M/D" (no leading zero on month/day — matches the design's "5/14" labels).
    public static func mdShort(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 1)/\(c.day ?? 1)"
    }

    public static func isToday(_ d: Date, calendar: Calendar = .current,
                               now: Date = Date()) -> Bool {
        calendar.isDate(d, inSameDayAs: now)
    }

    // MARK: - Model shortener

    /// shortenModel: prefix-strip + family-strip + nice display name.
    /// 1:1 with `ccgauge-refer/lib/utils.ts#shortenModel`.
    public static func shortenModel(_ model: String) -> String {
        cacheLock.lock()
        if let cached = shortenCache[model] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let result = shortenModelUncached(model)

        cacheLock.lock()
        shortenCache[model] = result
        cacheLock.unlock()
        return result
    }

    private static func shortenModelUncached(_ model: String) -> String {
        if model.isEmpty { return "(unknown)" }
        var s = model.replacingMatches(using: modelPrefixRegex, with: "")
        let lower = s.lowercased()
        if lower.hasPrefix("gpt-") {
            let rest = String(s.dropFirst(4))
            let parts = rest.split(separator: "-").map { p -> String in
                switch p.lowercased() {
                case "mini": return "Mini"
                case "nano": return "Nano"
                case "pro": return "Pro"
                case "turbo": return "Turbo"
                case "preview": return "Preview"
                default: return String(p)
                }
            }
            return "GPT-" + parts.joined(separator: " ")
        }
        if lower.rangeOfMatch(using: oSeriesRegex) != nil {
            return s.uppercased()
        }
        // Claude path: drop trailing -YYYYMMDD then drop `claude-`.
        s = s.replacingMatches(using: dateSuffixRegex, with: "")
        s = s.replacingMatches(using: claudePrefixRegex, with: "")
        let parts = s.split(separator: "-").map(String.init)
        if parts.count >= 2 {
            return capitalize(parts[0]) + " " + parts.dropFirst().joined(separator: ".")
        }
        return capitalize(s.replacingOccurrences(of: "-", with: " "))
    }

    // MARK: - Private helpers

    private static func capitalize(_ s: String) -> String {
        s.split(separator: " ").map { word -> String in
            guard let first = word.first else { return String(word) }
            return first.uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private static func trim(_ s: String, suffix: String = ".0") -> String {
        s.hasSuffix(suffix) ? String(s.dropLast(suffix.count)) : s
    }
}

public let currencySymbols: [String: String] = [
    "USD": "$", "CNY": "¥", "EUR": "€", "JPY": "¥"
]
