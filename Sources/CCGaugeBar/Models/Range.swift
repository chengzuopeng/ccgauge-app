// Range.swift — time-range filter used by Overview + Usage pages.
//
// Mirrors ccgauge-refer/lib/range.ts. The dashboard uses lowercase
// "1d/7d/30d/all"; this app uses uppercase to match the design's UI strings
// ("1D / 7D / 30D / 全部"). They map the same way to date windows.

import Foundation

public enum Range: String, CaseIterable, Codable, Hashable, Sendable {
    case d1  = "1D"
    case d7  = "7D"
    case d30 = "30D"
    case all = "ALL"

    public var displayLabel: String {
        displayLabel(lang: .zh)
    }

    public func displayLabel(lang: Lang) -> String {
        switch self {
        case .all: return L10n.t("range.all", lang: lang)
        default:   return rawValue
        }
    }
}

/// Granularity for trend-chart bucketing. Mirrors lib/aggregator/index.ts.
public enum Granularity: String, Sendable {
    case hour
    case day
}

public struct DateRange: Equatable, Sendable {
    public let from: Date?   // nil = no lower bound
    public let to: Date?     // nil = "now" (no upper bound)

    public init(from: Date?, to: Date?) {
        self.from = from
        self.to = to
    }
}

/// Map a UI Range to concrete [from, to] dates.
///
/// `1D` means "today since local midnight" (matching the design's 24
/// hourly buckets, not "rolling 24h"). `7D/30D` are rolling windows from
/// `now - N days`.
public func rangeToDates(_ r: Range, now: Date = Date(),
                         calendar: Calendar = .current) -> DateRange {
    switch r {
    case .all:
        return DateRange(from: nil, to: nil)
    case .d1:
        let from = calendar.startOfDay(for: now)
        return DateRange(from: from, to: nil)
    case .d7:
        return DateRange(from: calendar.date(byAdding: .day, value: -7, to: now),
                         to: nil)
    case .d30:
        return DateRange(from: calendar.date(byAdding: .day, value: -30, to: now),
                         to: nil)
    }
}

/// Granularity for a given Range (Overview's design-fixed mapping).
public func granularityFor(_ r: Range) -> Granularity {
    r == .d1 ? .hour : .day
}

/// Number of buckets to render. 1D → 24 hours, 7D → 7 days, 30D → 30 days,
/// ALL → 30 days (we don't draw an unbounded chart; ALL is for usage page only).
public func bucketCountFor(_ r: Range) -> Int {
    switch r {
    case .d1:  return 24
    case .d7:  return 7
    case .d30: return 30
    case .all: return 30
    }
}

// MARK: - Bucket key generation

/// Bucket a timestamp into a (key, label) pair under the given granularity.
/// Mirrors `lib/aggregator/index.ts#bucketKey` (1:1).
public func bucketKey(_ ts: Date, gran: Granularity,
                      calendar: Calendar = .current) -> (key: String, label: String) {
    let comps = calendar.dateComponents([.year, .month, .day, .hour], from: ts)
    let yyyy = String(format: "%04d", comps.year ?? 1970)
    let mm = String(format: "%02d", comps.month ?? 1)
    let dd = String(format: "%02d", comps.day ?? 1)
    let hh = String(format: "%02d", comps.hour ?? 0)
    switch gran {
    case .hour:
        return ("\(yyyy)-\(mm)-\(dd)T\(hh)", "\(mm)/\(dd) \(hh):00")
    case .day:
        return ("\(yyyy)-\(mm)-\(dd)", "\(mm)/\(dd)")
    }
}

/// Enumerate the empty bucket scaffolding for a range, so the trend chart
/// always renders the right number of bars (filled with 0s where there's no data).
public func enumerateBuckets(for r: Range, now: Date = Date(),
                             calendar: Calendar = .current) -> [(key: String, label: String, date: Date)] {
    var out: [(String, String, Date)] = []
    switch r {
    case .d1:
        let start = calendar.startOfDay(for: now)
        for h in 0..<24 {
            guard let d = calendar.date(byAdding: .hour, value: h, to: start) else { continue }
            let bk = bucketKey(d, gran: .hour, calendar: calendar)
            out.append((bk.key, String(format: "%02d", h), d))
        }
    case .d7:
        for offset in stride(from: -6, through: 0, by: 1) {
            guard let d = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let bk = bucketKey(d, gran: .day, calendar: calendar)
            out.append((bk.key, bk.label, d))
        }
    case .d30:
        for offset in stride(from: -29, through: 0, by: 1) {
            guard let d = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let bk = bucketKey(d, gran: .day, calendar: calendar)
            out.append((bk.key, bk.label, d))
        }
    case .all:
        // ALL doesn't have a chart; return last 30 days as a sensible default
        for offset in stride(from: -29, through: 0, by: 1) {
            guard let d = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let bk = bucketKey(d, gran: .day, calendar: calendar)
            out.append((bk.key, bk.label, d))
        }
    }
    return out
}
