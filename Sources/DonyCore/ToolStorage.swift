import Foundation

public struct ToolStorageItem: Identifiable, Sendable {
    public var id: String { candidate.id }
    public let candidate: FileCandidate
    public let owners: Set<AITool>
    public let isEligible: Bool
    public let reason: String
}
public struct ToolStorageResult: Sendable {
    public var items: [ToolStorageItem] = []
    public var issues: [ScanIssue] = []
    public var recognizedTools: Set<AITool> = []
    public var cancelled = false
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.candidate.bytes } }
    public var eligible: [ToolStorageItem] { cancelled ? [] : items.filter(\.isEligible) }
    public init() {}
}
public enum ToolStorage {
    private struct Location {
        let root: URL
        var owners: Set<AITool>
        let kind: CandidateKind
    }
    private static func locations(home: URL) -> [Location] {
        let bundleIDs: [AITool: [String]] = [
            .chatGPT: ["com.openai.chat"], .codex: ["com.openai.codex"],
            .claude: ["com.anthropic.claudefordesktop", "com.anthropic.claude"],
            .cursor: ["com.todesktop.230313mzl4w4u92"], .vscode: ["com.microsoft.VSCode"],
            .windsurf: ["com.exafunction.windsurf"], .terminal: ["com.apple.Terminal", "com.googlecode.iterm2"]
        ]
        var result: [String: Location] = [:]
        func add(_ path: String, owners: Set<AITool>, kind: CandidateKind) {
            let root = home.appendingPathComponent(path)
            if var existing = result[root.path] {
                existing.owners.formUnion(owners); result[root.path] = existing
            } else { result[root.path] = Location(root: root, owners: owners, kind: kind) }
        }
        for tool in AITool.allCases where tool != .other {
            let aliases = Set([tool.title] + tool.executableNames + (bundleIDs[tool] ?? []) + (tool == .vscode ? ["Code"] : []))
            let owners: Set<AITool> = tool == .vscode ? [.vscode, .copilot] : [tool]
            for alias in aliases {
                add("Library/Caches/" + alias, owners: owners, kind: .cache)
                add("Library/Logs/" + alias, owners: owners, kind: .log)
                for cache in ["Cache", "Code Cache", "GPUCache", "ShaderCache"] {
                    add("Library/Application Support/" + alias + "/" + cache, owners: owners, kind: .cache)
                }
            }
        }
        add(".codex/log", owners: [.codex], kind: .log)
        add(".claude/debug", owners: [.claude], kind: .log)
        add(".cache/opencode", owners: [.opencode], kind: .cache)
        return result.values.sorted { $0.root.path < $1.root.path }
    }
    private static let protectedNames: Set<String> = Set([
        ".git", ".hg", ".svn", "sessions", "archived_sessions", "projects", "worktrees",
        "auth.json", "credentials.json", "tokens.json", "settings.json", "settings.local.json",
        "config.json", "config.toml", "AGENTS.md", "CLAUDE.md", "GEMINI.md", "MEMORY.md"
    ]).union(ProjectCleanup.markers)
    private static func protected(_ url: URL, root: URL) -> Bool {
        let relative = String(url.path.dropFirst(root.path.count + 1))
        return relative.split(separator: "/").contains { part in
            let name = String(part)
            let lower = name.lowercased()
            return protectedNames.contains(name) || lower.contains("credential") ||
                lower.hasPrefix("auth.") || lower.hasSuffix(".jsonl") ||
                lower.contains(".sqlite") || lower.hasSuffix(".db") || lower.hasSuffix(".vscdb") ||
                lower.hasSuffix(".db-wal") || lower.hasSuffix(".db-shm")
        }
    }
    private static func containsProject(_ folder: URL) throws -> Bool {
        for marker in ProjectCleanup.markers {
            if try FileSafety.metadataIfPresent(folder.appendingPathComponent(marker)) != nil { return true }
        }
        return false
    }
    private static func checkRoot(_ root: URL) throws {
        guard try FileSafety.fingerprint(root).isDirectory,
              try FileSafety.canonicalRoot(root).path == root.path,
              try !containsProject(root) else { throw DonyError.unsafePath }
    }
    private static func eligible(_ candidate: FileCandidate, owners: Set<AITool>, running: Set<AITool>, days: Int, now: Date) -> Bool {
        owners.isDisjoint(with: running) && (1...3650).contains(days) &&
            Double(candidate.fingerprint.seconds) + Double(candidate.fingerprint.nanoseconds) / 1e9 <= now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
    }
    public static func scan(tools: Set<AITool>, home: URL = FileManager.default.homeDirectoryForCurrentUser, runningTools: Set<AITool>, days: Int, token: ScanToken, now: Date = Date(), progress: Scanner.Progress? = nil) -> ToolStorageResult {
        var result = ToolStorageResult()
        var seen = Set<String>(); var visited = 0
        do {
            try token.check()
            let base = try FileSafety.canonicalRoot(home)
            for location in locations(home: base) where !location.owners.isDisjoint(with: tools) {
                try token.check()
                do {
                    guard try FileSafety.metadataIfPresent(location.root) != nil else { continue }
                    try checkRoot(location.root)
                    result.recognizedTools.formUnion(location.owners.intersection(tools))
                    try ProjectFileWalker.walk(root: location.root, token: token, shouldDescend: {
                        !protected($0, root: location.root) && (try? containsProject($0)) == false
                    }) { url, fingerprint in
                        visited += 1
                        if visited.isMultiple(of: 250) { progress?(visited, location.owners.map(\.title).sorted().joined(separator: " · ")) }
                        guard fingerprint.isRegular, !protected(url, root: location.root), seen.insert(url.path).inserted else { return }
                        if location.kind == .log && !["log", "txt", "out"].contains(url.pathExtension.lowercased()) { return }
                        let candidate = try FileCandidate.capture(url: url, root: location.root, kind: location.kind, token: token)
                        let allowed = eligible(candidate, owners: location.owners, running: runningTools, days: days, now: now)
                        let reason = !location.owners.isDisjoint(with: runningTools) ? "사용 중인 도구 · 종료 후 다시 검사" : allowed ? "\(days)일 이상 지난 캐시·로그" : "최근 변경 · 보관"
                        result.items.append(ToolStorageItem(candidate: candidate, owners: location.owners, isEligible: allowed, reason: reason))
                    }
                } catch {
                    if token.isCancelled { throw DonyError.cancelled }
                    if result.issues.count < 100 { result.issues.append(ScanIssue(path: location.root.path, error: error)) }
                }
            }
        } catch {
            if !token.isCancelled { result.issues.append(ScanIssue(path: home.path, error: error)) }
        }
        result.cancelled = token.isCancelled
        if result.cancelled { result.items.removeAll() }
        result.items.sort { $0.candidate.bytes > $1.candidate.bytes }
        return result
    }
    public static func validate(_ item: ToolStorageItem, home: URL = FileManager.default.homeDirectoryForCurrentUser, runningTools: Set<AITool>, days: Int, token: ScanToken, now: Date = Date()) throws {
        try token.check()
        let base = try FileSafety.canonicalRoot(home)
        guard item.isEligible, let location = locations(home: base).first(where: { $0.root.path == item.candidate.root.path }),
              item.owners == location.owners, item.candidate.kind == location.kind,
              item.candidate.fingerprint.isRegular, !protected(item.candidate.url, root: location.root),
              FileSafety.isWithin(item.candidate.url, root: location.root) else { throw DonyError.unsafePath }
        try checkRoot(location.root)
        var parent = item.candidate.url.deletingLastPathComponent()
        while parent.path != location.root.path {
            guard FileSafety.isWithin(parent, root: location.root), try !containsProject(parent) else { throw DonyError.unsafePath }
            parent.deleteLastPathComponent()
        }
        guard item.owners.isDisjoint(with: runningTools) else { throw DonyError.protectedProcess }
        guard eligible(item.candidate, owners: item.owners, running: runningTools, days: days, now: now) else { throw DonyError.changed }
        try FileSafety.validate(item.candidate, token: token)
    }
}
public enum DevelopmentPressurePolicy {
    public static func shouldReview(pressure: MemoryPressure, duration: TimeInterval, sinceLastReview: TimeInterval) -> Bool {
        (pressure == .warning || pressure == .critical) && duration >= 30 && sinceLastReview >= 600
    }
}
