// ScanIndexPersistence.swift - on-disk cache for parsed JSONL file entries.

import Foundation

struct ScanFileEntry: Codable, Sendable {
    let source: ProviderId
    let parserVersion: String
    let mtimeMs: Int64
    let size: Int64
    let assistant: [AssistantRecord]
    let user: [UserRecord]
    let parentLinks: [ParentLink]
}

enum ScanParserVersions {
    static func current(for source: ProviderId) -> String {
        switch source {
        case .claude: return ClaudeParser.parserVersion
        case .codex: return CodexParser.parserVersion
        }
    }
}

enum ScanIndexPersistence {
    private static let schemaVersion = 1

    private struct PersistedIndex: Codable {
        let schemaVersion: Int
        let savedAt: Date
        let files: [PersistedFileEntry]
    }

    private struct PersistedFileEntry: Codable {
        let filePath: String
        let entry: ScanFileEntry
    }

    static func load() -> [String: ScanFileEntry] {
        let url = indexURL()
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let persisted = try decoder.decode(PersistedIndex.self, from: data)
            guard persisted.schemaVersion == schemaVersion else {
                PerfLog.log("index.load.skip schema=\(persisted.schemaVersion)")
                return [:]
            }

            var out: [String: ScanFileEntry] = [:]
            out.reserveCapacity(persisted.files.count)
            for file in persisted.files {
                let path = normalizePersistedPath(file.filePath)
                let entry = file.entry
                guard entry.parserVersion == ScanParserVersions.current(for: entry.source) else { continue }
                out[path] = entry
            }
            PerfLog.log("index.load files=\(out.count)")
            return out
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        } catch {
            PerfLog.logError("index.load.error", error)
            return [:]
        }
    }

    static func save(cache: [String: ScanFileEntry]) {
        let url = indexURL()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let files = cache.map { path, entry in
                PersistedFileEntry(filePath: path, entry: entry)
            }.sorted { $0.filePath < $1.filePath }

            let payload = PersistedIndex(schemaVersion: schemaVersion,
                                         savedAt: Date(),
                                         files: files)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            let tmp = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).tmp-\(ProcessInfo.processInfo.processIdentifier)")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
            PerfLog.log("index.save files=\(files.count)")
        } catch {
            PerfLog.logError("index.save.error", error)
        }
    }

    private static func indexURL() -> URL {
        let base: URL
        if let env = ProcessInfo.processInfo.environment["CCGAUGE_STATE_DIR"], !env.isEmpty {
            base = URL(fileURLWithPath: env, isDirectory: true)
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
                .appendingPathComponent("CCGaugeBar", isDirectory: true)
        }
        return base
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("index-v\(schemaVersion).json")
    }

    private static func normalizePersistedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
