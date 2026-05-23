// ProjectLabel.swift — worktree-aware label resolver for a cwd path.
//
// 1:1 port of ccgauge-refer/lib/project-label.ts.
//
// Goal: when a record's cwd lives inside a git worktree or a Claude Code
// `.claude/worktrees/...` directory, display
//     "<main-repo> (<worktree-name>)"
// so the dashboard doesn't show just "playwright" when the project is
// actually "ai-self-web (playwright)".
//
// Resolution order:
//   1. Path-pattern fast path — works even when the worktree dir is gone
//      (Claude Code's short-lived worktrees commonly disappear).
//   2. Read `<cwd>/.git` as a file; if it contains
//        gitdir: <main>/.git/worktrees/<name>
//      pull main + name out.
//   3. Fallback: plain basename.
//
// Per-process cache: worktrees are essentially static during the app's
// lifetime; we never evict. If the user renames a worktree mid-session,
// the label is stale until restart (acceptable; rare).

import Foundation

public enum ProjectLabel {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]

    /// Path-pattern fast path: matches both `.git/worktrees/<name>` and
    /// Claude Code's `.claude/worktrees/<name>` layouts.
    private static let cwdWorktreePattern =
        #"^(.+?)[/\\](?:\.git|\.claude)[/\\]worktrees[/\\]([^/\\]+)(?:[/\\].*)?$"#
    private static let gitdirPattern =
        #"^(.+?)[/\\]\.git[/\\]worktrees[/\\]([^/\\]+)[/\\]?$"#

    public static func resolve(_ cwd: String) -> String {
        lock.lock()
        if let cached = cache[cwd] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let label = compute(cwd)

        lock.lock()
        cache[cwd] = label
        lock.unlock()
        return label
    }

    /// Test helper.
    public static func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private static func compute(_ cwd: String) -> String {
        let fallback = projectNameFromCwd(cwd)
        if cwd.isEmpty { return fallback }

        // 1. Path-pattern fast path (handles deleted worktrees too).
        if let (main, wt) = matchTwoCaptureGroups(cwd, pattern: cwdWorktreePattern) {
            let mainName = (main as NSString).lastPathComponent
            return "\(mainName.isEmpty ? main : mainName) (\(wt))"
        }

        // 2. Read .git file (worktrees have it as a FILE pointing at the
        //    main repo, plain repos have it as a DIRECTORY).
        let gitPath = "\(cwd)/.git"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: gitPath),
           let type = attrs[.type] as? FileAttributeType,
           type == .typeRegular,
           let text = try? String(contentsOfFile: gitPath, encoding: .utf8) {
            let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
            if let m = matchOneCaptureGroup(firstLine, pattern: #"^gitdir:\s*(.+)$"#) {
                let gitdir = m.trimmingCharacters(in: .whitespaces)
                if let (main, wt) = matchTwoCaptureGroups(gitdir, pattern: gitdirPattern) {
                    let mainName = (main as NSString).lastPathComponent
                    return "\(mainName.isEmpty ? main : mainName) (\(wt))"
                }
            }
        }

        // 3. Plain basename.
        return fallback
    }

    public static func projectNameFromCwd(_ cwd: String) -> String {
        if cwd.isEmpty { return "(unknown)" }
        // Trim trailing separators (posix and windows) before taking the
        // last segment; protects against `"/Users/me/proj/"` style inputs.
        let trimmed = cwd.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        let parts = trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        return parts.last.map(String.init) ?? cwd
    }

    // MARK: regex helpers (NSRegularExpression with capture groups)

    private static func matchOneCaptureGroup(_ s: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: s, range: range), m.numberOfRanges >= 2,
              m.range(at: 1).location != NSNotFound
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func matchTwoCaptureGroups(_ s: String, pattern: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: s, range: range), m.numberOfRanges >= 3,
              m.range(at: 1).location != NSNotFound,
              m.range(at: 2).location != NSNotFound
        else { return nil }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
    }
}
