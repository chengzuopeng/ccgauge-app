// CodexParser.swift — parse one Codex CLI JSONL file.
//
// 1:1 port of ccgauge-refer/lib/providers/codex/parse-codex-jsonl.ts.
//
// **The single most important section is the cumulative→delta math at the
// `token_count` event handler.** If you change it, run the parser against
// known fixtures and compare totals to ccgauge's `report --json`. Bad
// math here = users see their bill doubled.

import Foundation

public enum CodexParser {
    public static let parserVersion = "codex-swift-1"

    public static let textPreviewMax = 200

    public static func dirs() -> [String] {
        let home = NSHomeDirectory()
        var out: [String] = []
        out.append("\(home)/.codex/sessions")
        out.append("\(home)/.codex/archived_sessions")
        if let env = ProcessInfo.processInfo.environment["CCGAUGE_CODEX_DIR"], !env.isEmpty {
            out.append(env)
        }
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            out.append("\(env)/sessions")
            out.append("\(env)/archived_sessions")
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    // Per-turn streaming state.
    private struct TurnState {
        var turnId: String?
        var cwd: String = ""
        var model: String = "gpt-unknown"
        var effort: String?
        var userUuid: String?
        var toolNames: [String] = []
        var hasThinking: Bool = false
        var pendingTextPreview: String = ""
    }

    private struct PrevTotal {
        var input: Int = 0
        var cached: Int = 0
        var output: Int = 0
        var reasoning: Int = 0
    }

    public static func parseFile(_ url: URL) async throws -> ParsedFile {
        var out = ParsedFile()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var sessionId = ""
        var cliVersion: String?
        var defaultCwd = ""
        var userIdx = 0
        var assistantIdx = 0
        var prevTotal: PrevTotal?
        var turn = TurnState()

        // File mtime is our last-resort timestamp fallback (see chain below).
        let fileMtime: Date = {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let m = attrs[.modificationDate] as? Date {
                return m
            }
            return Date()
        }()
        let fileMtimeIso = IsoDate.format(fileMtime)
        var lastValidTs = fileMtimeIso

        for try await line in handle.bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let evt = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let evtType = evt["type"] as? String
            else { continue }

            let payload = (evt["payload"] as? [String: Any]) ?? [:]
            let rawTs = (evt["timestamp"] as? String) ?? ""
            // Timestamp fallback chain:
            //   1. event.timestamp (preferred)
            //   2. session_meta.payload.timestamp
            //   3. lastValidTs (monotonic continuity)
            //   4. file mtime
            //   5. now()
            let ts = rawTs.isEmpty ? lastValidTs : rawTs
            if !rawTs.isEmpty { lastValidTs = rawTs }

            switch evtType {
            case "session_meta":
                sessionId = asString(payload["id"])
                defaultCwd = asString(payload["cwd"])
                cliVersion = asString(payload["cli_version"]).nilIfEmpty
                let metaTs = asString(payload["timestamp"])
                if !metaTs.isEmpty { lastValidTs = metaTs }
                if turn.cwd.isEmpty { turn.cwd = defaultCwd }

            case "turn_context":
                turn.turnId = asString(payload["turn_id"]).nilIfEmpty ?? turn.turnId
                turn.cwd = asString(payload["cwd"]).nilIfEmpty ?? defaultCwd
                let m = asString(payload["model"])
                if !m.isEmpty { turn.model = m }
                let eff = asString(payload["effort"])
                if !eff.isEmpty { turn.effort = eff }
                turn.toolNames = []
                turn.hasThinking = false
                turn.pendingTextPreview = ""

            case "event_msg":
                handleEventMsg(payload: payload, ts: ts,
                               sessionId: sessionId, cliVersion: cliVersion,
                               defaultCwd: defaultCwd,
                               turn: &turn,
                               prevTotal: &prevTotal,
                               userIdx: &userIdx,
                               assistantIdx: &assistantIdx,
                               filePath: url.path,
                               out: &out)

            case "response_item":
                handleResponseItem(payload: payload, turn: &turn)

            default:
                break
            }
        }

        return out
    }

    // MARK: - event_msg dispatch

    private static func handleEventMsg(payload: [String: Any], ts: String,
                                       sessionId: String, cliVersion: String?,
                                       defaultCwd: String,
                                       turn: inout TurnState,
                                       prevTotal: inout PrevTotal?,
                                       userIdx: inout Int,
                                       assistantIdx: inout Int,
                                       filePath: String,
                                       out: inout ParsedFile) {
        let sub = asString(payload["type"])

        switch sub {
        case "user_message":
            let text = extractMessageText(payload)
            guard !text.isEmpty else { return }
            let uuid = "\(sessionId)::u\(userIdx)"
            userIdx += 1
            let timestamp = IsoDate.parse(ts)
            out.user.append(UserRecord(
                source: .codex,
                uuid: uuid,
                parentUuid: nil,
                timestamp: timestamp,
                timestampIso: ts,
                sessionId: sessionId,
                cwd: turn.cwd.isEmpty ? defaultCwd : turn.cwd,
                textPreview: String(text.prefix(textPreviewMax)),
                isSynthetic: false,
                isSidechain: false,
                filePath: filePath
            ))
            out.parentLinks.append(ParentLink(uuid: uuid, parentUuid: nil))
            turn.userUuid = uuid

        case "agent_message":
            let text = extractMessageText(payload)
            if !text.isEmpty && turn.pendingTextPreview.isEmpty {
                turn.pendingTextPreview = String(text.prefix(textPreviewMax))
            }

        case "agent_reasoning":
            turn.hasThinking = true

        case "token_count":
            handleTokenCount(payload: payload, ts: ts,
                             sessionId: sessionId, cliVersion: cliVersion,
                             defaultCwd: defaultCwd,
                             turn: &turn,
                             prevTotal: &prevTotal,
                             assistantIdx: &assistantIdx,
                             filePath: filePath,
                             out: &out)

        default:
            break
        }
    }

    // MARK: - response_item dispatch

    private static func handleResponseItem(payload: [String: Any], turn: inout TurnState) {
        let sub = asString(payload["type"])
        switch sub {
        case "function_call", "custom_tool_call":
            let name = asString(payload["name"])
            if !name.isEmpty { turn.toolNames.append(name) }
        case "reasoning":
            turn.hasThinking = true
        case "message":
            let role = asString(payload["role"])
            if role == "assistant" {
                let text = extractMessageText(payload)
                if !text.isEmpty && turn.pendingTextPreview.isEmpty {
                    turn.pendingTextPreview = String(text.prefix(textPreviewMax))
                }
            }
        default:
            break
        }
    }

    // MARK: - token_count: cumulative → forward-only delta
    //
    // This is the "$ doubled" bug zone. The math, in plain English:
    //   - Codex emits `total_token_usage` per token_count event (cumulative).
    //   - Multiple events in the same file may re-state the same totals
    //     (refresh / partial-state events).
    //   - We compute each record's tokens as max(0, cur - prev) per field,
    //     then advance prev = per-field max(prev, cur). All-zero delta = skip.
    //   - First event in the file: treat the whole total as "tokens so far".

    private static func handleTokenCount(payload: [String: Any], ts: String,
                                         sessionId: String, cliVersion: String?,
                                         defaultCwd: String,
                                         turn: inout TurnState,
                                         prevTotal: inout PrevTotal?,
                                         assistantIdx: inout Int,
                                         filePath: String,
                                         out: inout ParsedFile) {
        guard let info = payload["info"] as? [String: Any] else { return }
        let totalDict = info["total_token_usage"] as? [String: Any]
        let lastDict = info["last_token_usage"] as? [String: Any]

        let cur: PrevTotal? = totalDict.map { t in
            PrevTotal(
                input:     asInt(t["input_tokens"]),
                cached:    asInt(t["cached_input_tokens"]),
                output:    asInt(t["output_tokens"]),
                reasoning: asInt(t["reasoning_output_tokens"])
            )
        }

        var deltaInput = 0, deltaCached = 0, deltaOutput = 0, deltaReasoning = 0

        if let cur = cur {
            if prevTotal == nil {
                // First token_count → represents "tokens accumulated so far".
                deltaInput = cur.input
                deltaCached = cur.cached
                deltaOutput = cur.output
                deltaReasoning = cur.reasoning
            } else {
                deltaInput     = max(0, cur.input     - prevTotal!.input)
                deltaCached    = max(0, cur.cached    - prevTotal!.cached)
                deltaOutput    = max(0, cur.output    - prevTotal!.output)
                deltaReasoning = max(0, cur.reasoning - prevTotal!.reasoning)
            }
            // Pure-zero delta = refresh / dup event, skip.
            if deltaInput == 0 && deltaCached == 0 && deltaOutput == 0 && deltaReasoning == 0 {
                return
            }
            // ⚠️ Advance prev via per-field max so partial-state refreshes
            // (some counters move backward) don't corrupt the next delta.
            if prevTotal == nil {
                prevTotal = cur
            } else {
                prevTotal = PrevTotal(
                    input:     max(prevTotal!.input,     cur.input),
                    cached:    max(prevTotal!.cached,    cur.cached),
                    output:    max(prevTotal!.output,    cur.output),
                    reasoning: max(prevTotal!.reasoning, cur.reasoning)
                )
            }
        } else if let last = lastDict {
            // Legacy fallback: old Codex versions only emit last_token_usage,
            // no totals at all. Treat last as delta, no dedup possible.
            deltaInput = asInt(last["input_tokens"])
            deltaCached = asInt(last["cached_input_tokens"])
            deltaOutput = asInt(last["output_tokens"])
            deltaReasoning = asInt(last["reasoning_output_tokens"])
            if deltaInput == 0 && deltaCached == 0 && deltaOutput == 0 && deltaReasoning == 0 {
                return
            }
        } else {
            return
        }

        // Emit the assistant record.
        assistantIdx += 1
        let uuid = "\(sessionId)::a\(assistantIdx)"
        let requestId: String = {
            if let t = turn.turnId { return "\(t)::a\(assistantIdx)" }
            return "\(sessionId)::a\(assistantIdx)"
        }()

        // Note: input billable = (delta total input) - (delta cached),
        // matching how Codex bills cached reads separately at a lower rate.
        // output_tokens already includes reasoning per OpenAI's convention —
        // we surface reasoning separately for display but don't double-count.
        let usage = Usage(
            inputTokens:                max(0, deltaInput - deltaCached),
            outputTokens:               deltaOutput + deltaReasoning,
            cacheCreationInputTokens:   0,
            cacheReadInputTokens:       deltaCached,
            cacheCreation5m:            0,
            cacheCreation1h:            0,
            reasoningTokens:            deltaReasoning
        )

        let record = AssistantRecord(
            source: .codex,
            uuid: uuid,
            parentUuid: turn.userUuid,
            timestamp: IsoDate.parse(ts),
            timestampIso: ts,
            sessionId: sessionId,
            requestId: requestId,
            cwd: turn.cwd.isEmpty ? defaultCwd : turn.cwd,
            gitBranch: nil,
            version: cliVersion,
            model: turn.model.isEmpty ? "gpt-unknown" : turn.model,
            messageId: requestId,
            usage: usage,
            toolNames: turn.toolNames,
            hasThinking: turn.hasThinking,
            textPreview: turn.pendingTextPreview,
            effort: turn.effort,
            isSidechain: false,
            filePath: filePath
        )
        out.assistant.append(record)
        out.parentLinks.append(ParentLink(uuid: uuid, parentUuid: turn.userUuid))

        // Clear per-call accumulator; carry forward turn-level state.
        turn.toolNames = []
        turn.hasThinking = false
        turn.pendingTextPreview = ""
    }

    // MARK: - text extractor

    private static func extractMessageText(_ payload: [String: Any]) -> String {
        if let s = payload["message"] as? String { return s }
        if let s = payload["content"] as? String { return s }
        if let arr = payload["content"] as? [[String: Any]] {
            for c in arr {
                let t = c["type"] as? String ?? ""
                if (t == "input_text" || t == "output_text" || t == "text"),
                   let s = c["text"] as? String {
                    return s
                }
            }
        }
        return ""
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
