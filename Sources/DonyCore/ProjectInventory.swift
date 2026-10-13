import Foundation

public struct ProjectInventoryEntry: Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public var tools: Set<AITool>
    public var bytes: Int64 = 0
    public var files = 0
    public var generatedBytes: Int64 = 0
    public var contextBytes: Int64 = 0
    public var contextFiles = 0
    public var lastActivity: Date?
    public var managedWorktree = false
    public var backup = GitBackupReport(false, "원격 미확인")
    public var issues: [ScanIssue] = []
    public init(path: String, tools: Set<AITool>) { self.path = path; self.tools = tools }
}

public enum ProjectInventory {
    // Instructions, memories and agent definitions are user work, not disposable caches.
    public static let contextPaths = ["AGENTS.md", "CLAUDE.md", "GEMINI.md", "MEMORY.md", ".claude/agents", ".claude/skills", ".claude/commands", ".claude/rules", ".claude/settings.json", ".claude/settings.local.json", ".codex/config.toml", ".codex/skills", ".cursor/rules", ".github/copilot-instructions.md"]
    public static func inspect(projects: [LinkedProject], token: ScanToken, progress: Scanner.Progress? = nil) -> [ProjectInventoryEntry] {
        var entries: [ProjectInventoryEntry] = []
        for path in Set(projects.map(\.path)).sorted() {
            if token.isCancelled { break }
            let links = projects.filter { $0.path == path }
            var entry = ProjectInventoryEntry(path: path, tools: Set(links.map(\.tool)))
            entry.lastActivity = links.compactMap(\.lastActivity).max()
            let root = (try? FileSafety.canonicalRoot(URL(fileURLWithPath: path))) ?? URL(fileURLWithPath: path)
            do {
                let fp = try FileSafety.fingerprint(root)
                guard fp.isDirectory, FileSafety.allowedRoot(root, kind: .project) else { throw DonyError.unsafePath }
                entry.managedWorktree = (try? FileSafety.fingerprint(root.appendingPathComponent(".git")))?.isRegular == true
                var failure: Error?
                guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in failure = error; return false }) else { throw DonyError.unsupported }
                var visited = 0
                for case let file as URL in iterator {
                    try token.check(); visited += 1
                    guard visited <= 100_000 else { throw DonyError.scanLimit }
                    let child = try FileSafety.fingerprint(file)
                    guard child.isDirectory || child.isRegular else { continue }
                    let date = Date(timeIntervalSince1970: Double(child.seconds))
                    entry.lastActivity = max(entry.lastActivity ?? .distantPast, date)
                    guard child.isRegular else { continue }
                    let relative = String(file.path.dropFirst(root.path.count + 1))
                    entry.bytes += child.size; entry.files += 1
                    if ProjectCleanup.generatedPaths.contains(where: { relative.hasPrefix($0 + "/") }) { entry.generatedBytes += child.size }
                    if contextPaths.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { entry.contextBytes += child.size; entry.contextFiles += 1 }
                    if visited.isMultiple(of: 250) { progress?(visited, root.lastPathComponent) }
                }
                if let failure { throw failure }
                progress?(visited, root.lastPathComponent + " · 원격 저장 확인")
                entry.backup = entry.managedWorktree ? GitBackupReport(false, "관리 도구 worktree") : GitBackup.check(root: root)
            } catch { if !token.isCancelled { entry.issues.append(ScanIssue(path: path, error: error)) } }
            entries.append(entry)
        }
        return entries
    }
    public static func discoverManagedWorktrees(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanToken) -> [LinkedProject] {
        var projects: [LinkedProject] = []
        for (relative, tool) in [(".codex/worktrees", AITool.codex), (".claude/worktrees", .claude)] {
            let base = (try? FileSafety.canonicalRoot(home.appendingPathComponent(relative))) ?? home.appendingPathComponent(relative)
            guard let iterator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            var count = 0
            for case let folder as URL in iterator {
                if token.isCancelled { return projects }; count += 1
                if count > 2000 { break }
                guard let fp = try? FileSafety.fingerprint(folder), fp.isDirectory else { continue }
                if (try? FileSafety.fingerprint(folder.appendingPathComponent(".git")))?.isRegular == true {
                    projects.append(LinkedProject(tool: tool, path: folder.path, enabled: false, discovered: true)); iterator.skipDescendants()
                } else if folder.path.dropFirst(base.path.count).split(separator: "/").count >= 2 { iterator.skipDescendants() }
            }
        }
        return projects
    }
}
