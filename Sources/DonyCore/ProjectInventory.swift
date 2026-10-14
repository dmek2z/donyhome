import Foundation

public struct ProjectInventoryEntry: Codable, Sendable, Identifiable {
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
    /// Filesystem providers may block inside open(2), beyond cooperative deadlines.
    /// Run each read-only inventory in a disposable process so cancellation stays responsive.
    public static func inspectIsolated(projects: [LinkedProject], executable: URL, token: ScanToken, progress: Scanner.Progress? = nil, timeout: TimeInterval = 20) -> [ProjectInventoryEntry] {
        var entries: [ProjectInventoryEntry] = []
        for path in Set(projects.map(\.path)).sorted() {
            if token.isCancelled { break }
            let links = projects.filter { $0.path == path }
            var entry = ProjectInventoryEntry(path: path, tools: Set(links.map(\.tool)))
            entry.lastActivity = links.compactMap(\.lastActivity).max()
            progress?(entries.count, URL(fileURLWithPath: path).lastPathComponent + " · 파일 확인")
            let log = FileManager.default.temporaryDirectory.appendingPathComponent("DonyHome-inventory-" + UUID().uuidString)
            let process = Process()
            do {
                guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw DonyError.unsupported }
                defer { try? FileManager.default.removeItem(at: log) }
                let handle = try FileHandle(forWritingTo: log)
                defer { try? handle.close() }
                process.executableURL = executable; process.arguments = ["--project-inventory", path]
                process.standardOutput = handle; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
                try process.run()
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && !token.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                if process.isRunning {
                    // SIGKILL also handles a helper blocked in a permission/provider syscall.
                    kill(process.processIdentifier, SIGKILL)
                    entry.issues.append(ScanIssue(path: path, message: token.isCancelled ? "검사 중단" : "폴더 응답 대기 초과 · 권한 또는 파일 동기화 상태를 확인해 주세요."))
                } else {
                    guard process.terminationStatus == 0, (try FileSafety.fingerprint(log)).size <= 65_536 else { throw DonyError.unsupported }
                    var result = try JSONDecoder().decode(ProjectInventoryEntry.self, from: Data(contentsOf: log))
                    guard result.path == path else { throw DonyError.unsafePath }
                    result.tools = entry.tools
                    result.lastActivity = max(result.lastActivity ?? .distantPast, entry.lastActivity ?? .distantPast)
                    entry = result
                }
            } catch { entry.issues.append(ScanIssue(path: path, error: error)) }
            entries.append(entry)
        }
        return entries
    }
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
                var visited = 0
                try ProjectFileWalker.walk(root: root, token: token) { file, child in
                    visited += 1
                    guard child.isDirectory || child.isRegular else { return }
                    let date = Date(timeIntervalSince1970: Double(child.seconds))
                    entry.lastActivity = max(entry.lastActivity ?? .distantPast, date)
                    if visited.isMultiple(of: 250) { progress?(visited, root.lastPathComponent) }
                    guard child.isRegular else { return }
                    let relative = String(file.path.dropFirst(root.path.count + 1))
                    entry.bytes += child.size; entry.files += 1
                    if ProjectCleanup.generatedPaths.contains(where: { relative.hasPrefix($0 + "/") }) { entry.generatedBytes += child.size }
                    if contextPaths.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { entry.contextBytes += child.size; entry.contextFiles += 1 }
                }
                progress?(visited, root.lastPathComponent + " · 원격 저장 확인")
                entry.backup = entry.managedWorktree ? GitBackupReport(false, "관리 도구 worktree") : GitBackup.check(root: root)
            } catch {
                entry.issues.append(token.isCancelled ? ScanIssue(path: path, message: "검사 중단 · 일부 결과") : ScanIssue(path: path, error: error))
            }
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
