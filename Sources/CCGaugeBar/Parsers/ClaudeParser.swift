// ClaudeParser.swift — parse one Claude Code JSONL file.
//
// 1:1 port of ccgauge-refer/lib/data-loader/parse-jsonl.ts.
// Each line is an independent JSON object; a malformed line is skipped
// (silently — matching the TS implementation).

import Foundation

public struct ParsedFile: Sendable {
    public var assistant: [AssistantRecord] = []
    public var user: [UserRecord] = []
    public var parentLinks: [ParentLink] = []

    public init() {}
}

public enum ClaudeParser {
    public static let parserVersion = "claude-swift-1"

    /// Hard cap on textPreview to keep memory under control even for very
    /// long prompts. Matches the TS implementation (200 chars).
    public static let textPreviewMax = 200

    public static func dirs() -> [String] {
        let home = NSHomeDirectory()
        var out: [String] = []
        out.append("\(home)/.claude/projects")
        out.append("\(home)/.config/claude/projects")
        if let env = ProcessInfo.processInfo.environment["CCGAUGE_CONFIG_DIR"], !env.isEmpty {
            out.append("\(env)/projects")
        }
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            out.append("\(env)/projects")
        }
        // dedupe while preserving order
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    public static func parseFile(_ url: URL) async throws -> ParsedFile {
        var out = ParsedFile()
        // FileHandle.bytes.lines reads UTF-8 lazily — ideal for multi-MB JSONL.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        for try await line in handle.bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }

            // Record every uuid → parentUuid link, before checking type.
            // `parentLinks` is the dedup-resistant parent map turn-grouping
            // walks.
            if let uuid = raw["uuid"] as? String {
                let parent = raw["parentUuid"] as? String
                out.parentLinks.append(ParentLink(uuid: uuid, parentUuid: parent))
            }

            switch raw["type"] as? String {
            case "assistant":
                if let a = parseAssistant(raw: raw, filePath: url.path) {
                    out.assistant.append(a)
                }
            case "user":
                if let u = parseUser(raw: raw, filePath: url.path) {
                    out.user.append(u)
                }
            default:
                break
            }
        }
        return out
    }

    // MARK: assistant

    private static func parseAssistant(raw: [String: Any], filePath: String) -> AssistantRecord? {
        guard let msg = raw["message"] as? [String: Any],
              let usageDict = msg["usage"] as? [String: Any]
        else { return nil }

        let model = (msg["model"] as? String) ?? ""
        // Skip the `<synthetic>` model rows Claude Code emits for tool-result
        // placeholders — they have no real usage attribution.
        guard !model.isEmpty, model != "<synthetic>" else { return nil }

        let messageId = (msg["id"] as? String) ?? (raw["uuid"] as? String) ?? ""
        let requestId = (raw["requestId"] as? String) ?? ""
        guard !messageId.isEmpty || !requestId.isEmpty else { return nil }

        // Cache buckets (nested object, may be missing).
        let cacheCreation = usageDict["cache_creation"] as? [String: Any]
        let usage = Usage(
            inputTokens:                asInt(usageDict["input_tokens"]),
            outputTokens:               asInt(usageDict["output_tokens"]),
            cacheCreationInputTokens:   asInt(usageDict["cache_creation_input_tokens"]),
            cacheReadInputTokens:       asInt(usageDict["cache_read_input_tokens"]),
            cacheCreation5m:            asInt(cacheCreation?["ephemeral_5m_input_tokens"]),
            cacheCreation1h:            asInt(cacheCreation?["ephemeral_1h_input_tokens"])
        )

        var toolNames: [String] = []
        var hasThinking = false
        var textPreview = ""
        if let content = msg["content"] as? [[String: Any]] {
            for c in content {
                let type = c["type"] as? String
                if type == "tool_use", let name = c["name"] as? String {
                    toolNames.append(name)
                } else if type == "thinking" {
                    hasThinking = true
                } else if type == "text", textPreview.isEmpty, let text = c["text"] as? String {
                    textPreview = String(text.prefix(textPreviewMax))
                }
            }
        }

        let timestampIso = (raw["timestamp"] as? String) ?? IsoDate.format(Date())
        let timestamp = IsoDate.parse(timestampIso)

        return AssistantRecord(
            source: .claude,
            uuid: (raw["uuid"] as? String) ?? messageId,
            parentUuid: raw["parentUuid"] as? String,
            timestamp: timestamp,
            timestampIso: timestampIso,
            sessionId: (raw["sessionId"] as? String) ?? "",
            requestId: requestId,
            cwd: (raw["cwd"] as? String) ?? "",
            gitBranch: raw["gitBranch"] as? String,
            version: raw["version"] as? String,
            model: model,
            messageId: messageId,
            usage: usage,
            toolNames: toolNames,
            hasThinking: hasThinking,
            textPreview: textPreview,
            effort: nil,
            isSidechain: (raw["isSidechain"] as? Bool) == true,
            filePath: filePath
        )
    }

    // MARK: user

    private static func parseUser(raw: [String: Any], filePath: String) -> UserRecord? {
        guard let uuid = raw["uuid"] as? String else { return nil }

        var textPreview = ""
        if let msg = raw["message"] as? [String: Any] {
            if let content = msg["content"] as? String {
                textPreview = String(content.prefix(textPreviewMax))
            } else if let content = msg["content"] as? [[String: Any]] {
                for c in content {
                    if c["type"] as? String == "text", let t = c["text"] as? String {
                        textPreview = String(t.prefix(textPreviewMax))
                        break
                    }
                }
            }
        }

        let isSidechain = (raw["isSidechain"] as? Bool) == true
        // Synthetic rule: sidechain (sub-agent first prompt) OR text matches
        // one of the known system-injected prefixes.
        let isSynthetic = isSidechain || isSyntheticUserText(textPreview)

        let timestampIso = (raw["timestamp"] as? String) ?? IsoDate.format(Date())
        let timestamp = IsoDate.parse(timestampIso)

        return UserRecord(
            source: .claude,
            uuid: uuid,
            parentUuid: raw["parentUuid"] as? String,
            timestamp: timestamp,
            timestampIso: timestampIso,
            sessionId: (raw["sessionId"] as? String) ?? "",
            cwd: (raw["cwd"] as? String) ?? "",
            textPreview: textPreview,
            isSynthetic: isSynthetic,
            isSidechain: isSidechain,
            filePath: filePath
        )
    }

    /// Mirrors `isSyntheticUserText` in parse-jsonl.ts — keep conservative:
    /// only patterns we're certain aren't human input. Adding a new prefix
    /// here should match upstream ccgauge first.
    public static func isSyntheticUserText(_ text: String) -> Bool {
        let t = text.drop(while: { $0.isWhitespace })
        if t.hasPrefix("Base directory for this skill:") { return true }
        if t.hasPrefix("<system-reminder>") { return true }
        if t.hasPrefix("Caveat: The messages below were generated by") { return true }
        return false
    }
}

// MARK: - Local helpers

@inline(__always)
func asInt(_ v: Any?) -> Int {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    return 0
}

@inline(__always)
func asString(_ v: Any?) -> String {
    (v as? String) ?? ""
}
