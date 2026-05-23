// Pricing.swift — built-in price tables + 5-level model→pricing resolver.
//
// 1:1 ported from:
//   ccgauge-refer/lib/pricing/builtin.ts
//   ccgauge-refer/lib/providers/codex/pricing.ts
//   ccgauge-refer/lib/providers/claude/index.ts#resolvePricing
//   ccgauge-refer/lib/pricing/cost-from-usage.ts
//
// All `Pricing` fields are USD per million tokens.

import Foundation

public struct Pricing: Hashable, Sendable {
    public let input: Double
    public let output: Double
    public let cacheCreation5m: Double
    public let cacheCreation1h: Double
    public let cacheRead: Double

    public init(input: Double, output: Double,
                cacheCreation5m: Double, cacheCreation1h: Double,
                cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheCreation5m = cacheCreation5m
        self.cacheCreation1h = cacheCreation1h
        self.cacheRead = cacheRead
    }
}

public struct CostBreakdown: Sendable {
    public var input: Double = 0
    public var output: Double = 0
    public var cacheCreation5m: Double = 0
    public var cacheCreation1h: Double = 0
    public var cacheRead: Double = 0
    public var total: Double = 0
    public var saved: Double = 0

    public static let zero = CostBreakdown()

    public init() {}
}

// MARK: - Tables

public enum ClaudePricing {
    /// Source: lib/pricing/builtin.ts (1:1).
    public static let table: [String: Pricing] = [
        "claude-opus-4-7":   Pricing(input: 5,    output: 25,   cacheCreation5m: 6.25,  cacheCreation1h: 10,   cacheRead: 0.5),
        "claude-opus-4-6":   Pricing(input: 5,    output: 25,   cacheCreation5m: 6.25,  cacheCreation1h: 10,   cacheRead: 0.5),
        "claude-opus-4-5":   Pricing(input: 5,    output: 25,   cacheCreation5m: 6.25,  cacheCreation1h: 10,   cacheRead: 0.5),
        "claude-opus-4-1":   Pricing(input: 15,   output: 75,   cacheCreation5m: 18.75, cacheCreation1h: 30,   cacheRead: 1.5),
        "claude-opus-4":     Pricing(input: 15,   output: 75,   cacheCreation5m: 18.75, cacheCreation1h: 30,   cacheRead: 1.5),
        "claude-sonnet-4-6": Pricing(input: 3,    output: 15,   cacheCreation5m: 3.75,  cacheCreation1h: 6,    cacheRead: 0.3),
        "claude-sonnet-4-5": Pricing(input: 3,    output: 15,   cacheCreation5m: 3.75,  cacheCreation1h: 6,    cacheRead: 0.3),
        "claude-sonnet-4":   Pricing(input: 3,    output: 15,   cacheCreation5m: 3.75,  cacheCreation1h: 6,    cacheRead: 0.3),
        "claude-sonnet-3-7": Pricing(input: 3,    output: 15,   cacheCreation5m: 3.75,  cacheCreation1h: 6,    cacheRead: 0.3),
        "claude-haiku-4-5":  Pricing(input: 1,    output: 5,    cacheCreation5m: 1.25,  cacheCreation1h: 2,    cacheRead: 0.1),
        "claude-haiku-3-5":  Pricing(input: 0.8,  output: 4,    cacheCreation5m: 1,     cacheCreation1h: 1.6,  cacheRead: 0.08),
        "claude-haiku-3":    Pricing(input: 0.25, output: 1.25, cacheCreation5m: 0.3,   cacheCreation1h: 0.5,  cacheRead: 0.03)
    ]

    public static let familyFallback: [String: Pricing] = [
        "opus":   table["claude-opus-4-7"]!,
        "sonnet": table["claude-sonnet-4-6"]!,
        "haiku":  table["claude-haiku-4-5"]!
    ]
}

public enum CodexPricing {
    /// Source: lib/providers/codex/pricing.ts (1:1).
    /// OpenAI has no cache-creation concept → those two fields stay 0.
    public static let table: [String: Pricing] = [
        "gpt-5":         Pricing(input: 1.25, output: 10,  cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.13),
        "gpt-5-mini":    Pricing(input: 0.25, output: 2,   cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.025),
        "gpt-5-nano":    Pricing(input: 0.05, output: 0.4, cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.005),
        "gpt-5.4":       Pricing(input: 1.25, output: 10,  cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.13),
        "gpt-5.5":       Pricing(input: 1.25, output: 10,  cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.13),
        "gpt-5.5-mini":  Pricing(input: 0.25, output: 2,   cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.025),
        "gpt-5.5-nano":  Pricing(input: 0.05, output: 0.4, cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.005),
        "gpt-4.1":       Pricing(input: 2,    output: 8,   cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.5),
        "gpt-4.1-mini":  Pricing(input: 0.4,  output: 1.6, cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.1),
        "o3":            Pricing(input: 2,    output: 8,   cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.5),
        "o4-mini":       Pricing(input: 1.1,  output: 4.4, cacheCreation5m: 0, cacheCreation1h: 0, cacheRead: 0.275)
    ]

    public static let familyFallback: [String: Pricing] = [
        "gpt": table["gpt-5"]!,
        "o":   table["o3"]!
    ]
}

// MARK: - Resolver

/// Top-level: dispatch to the right provider resolver.
public func resolvePricing(model: String, source: ProviderId) -> Pricing? {
    guard !model.isEmpty else { return nil }
    let key = "\(source.rawValue)::\(model)"
    if let cached = PricingCache.get(key) {
        return cached.pricing
    }

    let resolved: Pricing?
    switch source {
    case .claude: resolved = resolveClaudePricingUncached(model)
    case .codex:  resolved = resolveCodexPricingUncached(model)
    }
    PricingCache.set(key, pricing: resolved)
    return resolved
}

private struct PricingCacheEntry {
    let pricing: Pricing?
}

private enum PricingCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [String: PricingCacheEntry] = [:]

    static func get(_ key: String) -> PricingCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    static func set(_ key: String, pricing: Pricing?) {
        lock.lock()
        entries[key] = PricingCacheEntry(pricing: pricing)
        lock.unlock()
    }
}

private let dateSuffixRegex = try! NSRegularExpression(pattern: #"-\d{8}$"#)
private let claudePrefixRegex = try! NSRegularExpression(pattern: #"^(vertex_ai|bedrock|anthropic)/"#)
private let codexPrefixRegex = try! NSRegularExpression(pattern: #"^openai/"#)
private let oSeriesRegex = try! NSRegularExpression(pattern: #"^o\d"#)

public func resolveClaudePricing(_ model: String) -> Pricing? {
    resolvePricing(model: model, source: .claude)
}

private func resolveClaudePricingUncached(_ model: String) -> Pricing? {
    // 1. exact
    if let p = ClaudePricing.table[model] { return p }
    // 2. date-stripped (trailing -YYYYMMDD)
    let stripped = model.replacingMatches(using: dateSuffixRegex, with: "")
    if let p = ClaudePricing.table[stripped] { return p }
    // 3. prefix-stripped (vertex_ai/ | bedrock/ | anthropic/)
    let noPrefix = stripped.replacingMatches(using: claudePrefixRegex, with: "")
    if let p = ClaudePricing.table[noPrefix] { return p }
    // 4. family fallback
    let lower = model.lowercased()
    for family in ["opus", "sonnet", "haiku"] where lower.contains(family) {
        return ClaudePricing.familyFallback[family]
    }
    return nil
}

public func resolveCodexPricing(_ model: String) -> Pricing? {
    resolvePricing(model: model, source: .codex)
}

private func resolveCodexPricingUncached(_ model: String) -> Pricing? {
    if let p = CodexPricing.table[model] { return p }
    let stripped = model.replacingMatches(using: dateSuffixRegex, with: "")
    if let p = CodexPricing.table[stripped] { return p }
    let noPrefix = stripped.replacingMatches(using: codexPrefixRegex, with: "")
    if let p = CodexPricing.table[noPrefix] { return p }
    let lower = model.lowercased()
    if lower.hasPrefix("gpt-") || lower == "gpt" {
        return CodexPricing.familyFallback["gpt"]
    }
    if lower.rangeOfMatch(using: oSeriesRegex) != nil {
        return CodexPricing.familyFallback["o"]
    }
    return nil
}

// MARK: - Cost computation

private let PER_MTOK: Double = 1_000_000

/// Compute cost breakdown for one record's usage given a pricing table entry.
/// Returns all-zeros (no crash) when pricing is nil — mirrors the TS
/// implementation's defensive default.
public func costFromUsage(_ u: Usage, pricing: Pricing?) -> CostBreakdown {
    guard let p = pricing else { return .zero }

    var c = CostBreakdown()
    c.input  = Double(u.inputTokens)  / PER_MTOK * p.input
    c.output = Double(u.outputTokens) / PER_MTOK * p.output

    c.cacheCreation5m = Double(u.cacheCreation5m) / PER_MTOK * p.cacheCreation5m
    c.cacheCreation1h = Double(u.cacheCreation1h) / PER_MTOK * p.cacheCreation1h

    // Legacy fallback: old Claude records only fill `cache_creation_input_tokens`,
    // not the 5m/1h split → bill the whole thing at 5m rate (cheaper, safer).
    if c.cacheCreation5m + c.cacheCreation1h == 0 && u.cacheCreationInputTokens > 0 {
        c.cacheCreation5m = Double(u.cacheCreationInputTokens) / PER_MTOK * p.cacheCreation5m
    }

    c.cacheRead = Double(u.cacheReadInputTokens) / PER_MTOK * p.cacheRead
    c.total = c.input + c.output + c.cacheCreation5m + c.cacheCreation1h + c.cacheRead

    // Money saved by cache: cacheRead tokens × (input price - cacheRead price).
    c.saved = Double(u.cacheReadInputTokens) / PER_MTOK * (p.input - p.cacheRead)
    return c
}

public func costOfRecord(_ r: AssistantRecord) -> CostBreakdown {
    let p = resolvePricing(model: r.model, source: r.source)
    return costFromUsage(r.usage, pricing: p)
}

// MARK: - String regex helpers

extension String {
    func replacingMatches(of pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        return replacingMatches(using: regex, with: replacement)
    }

    func replacingMatches(using regex: NSRegularExpression, with replacement: String) -> String {
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: replacement)
    }

    /// Returns the first regex match's range as a String.Index range.
    /// Disambiguated as `Swift.Range<…>` because the app defines its own
    /// `Range` enum (used as a UI time-window selector) which would shadow
    /// the stdlib type at this call site.
    func rangeOfMatch(of pattern: String) -> Swift.Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return rangeOfMatch(using: regex)
    }

    func rangeOfMatch(using regex: NSRegularExpression) -> Swift.Range<String.Index>? {
        let nsRange = NSRange(startIndex..., in: self)
        guard let m = regex.firstMatch(in: self, range: nsRange) else { return nil }
        return Swift.Range(m.range, in: self)
    }
}
