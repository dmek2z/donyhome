import Foundation
import DonySystemBridge

public struct ProjectDiscoveryResult: Sendable {
    public var projects: [LinkedProject] = []
    public var issues: [ScanIssue] = []
}
public enum ProjectDiscovery {
    /// Only recognized metadata keys become paths; conversational text is ignored.
    public static func paths(in data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var paths: [String] = []
        if let cwd = object["cwd"] as? String, cwd.hasPrefix("/") { paths.append(cwd) }
        if let payload = object["payload"] as? [String: Any], let cwd = payload["cwd"] as? String, cwd.hasPrefix("/") { paths.append(cwd) }
        if let folder = object["folder"] as? String, let url = URL(string: folder), url.isFileURL { paths.append(url.path) }
        return paths
    }
    public static func activePaths(processes: [ProcessReading], currentUID: UInt32) -> [String] {
        var paths = Set<String>()
        for process in processes where process.uid == currentUID {
            var buffer = [CChar](repeating: 0, count: 4096)
            if dc_process_cwd(process.pid, &buffer, Int32(buffer.count)) != 0 { paths.insert(String(cString: buffer)) }
        }
        return Array(paths)
    }
    public static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanToken) -> ProjectDiscoveryResult {
        var result = ProjectDiscoveryResult()
        func add(tool: AITool, path: String, date: Date?) {
            guard let root = try? ProjectCleanup.projectRoot(path) else { return }
            if let index = result.projects.firstIndex(where: { $0.tool == tool && $0.path == root.path }) {
                result.projects[index].lastActivity = max(result.projects[index].lastActivity ?? .distantPast, date ?? .distantPast)
            } else { result.projects.append(LinkedProject(tool: tool, path: root.path, lastActivity: date, enabled: false, discovered: true)) }
        }
        // Read only cwd and activity columns from Codex's local thread index.
        let codex = home.appendingPathComponent(".codex")
        do {
            if FileManager.default.fileExists(atPath: codex.path) {
                let databases = try FileManager.default.contentsOfDirectory(at: codex, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
                if let database = databases.first {
                    try token.check()
                    let query = "SELECT cwd, MAX(updated_at) AS updated FROM threads GROUP BY cwd LIMIT 2000;"
                    let command = try CommandRunner.run(CommandSpec(executable: "/usr/bin/sqlite3", arguments: ["-readonly", "-json", database.path, query], requiresAdmin: false), timeout: 5)
                    guard command.success, let data = command.output.data(using: .utf8), let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw DonyError.unsupported }
                    for row in rows {
                        try token.check()
                        if let path = row["cwd"] as? String { add(tool: .codex, path: path, date: (row["updated"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }) }
                    }
                }
            }
        } catch { if !token.isCancelled { result.issues.append(ScanIssue(path: codex.path, error: error)) } }
        // Claude JSONL session headers and Cursor workspace metadata are bounded reads.
        for (relative, tool) in [(".claude/projects", AITool.claude), ("Library/Application Support/Cursor/User/workspaceStorage", .cursor)] {
            let root = home.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: root.path), !token.isCancelled else { continue }
            do {
                var failure: Error?
                guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in failure = error; return false }) else { throw DonyError.unsupported }
                var count = 0
                for case let file as URL in iterator {
                    try token.check(); count += 1
                    guard count <= 10_000 else { throw DonyError.scanLimit }
                    let fp = try FileSafety.fingerprint(file)
                    if !fp.isDirectory && !fp.isRegular { iterator.skipDescendants(); continue }
                    guard fp.isRegular, (tool == .claude ? file.pathExtension == "jsonl" : file.lastPathComponent == "workspace.json") else { continue }
                    let handle = try FileHandle(forReadingFrom: file)
                    let data = try handle.read(upToCount: 65_536) ?? Data(); try handle.close()
                    let date: Date
                    if tool == .cursor {
                        let state = file.deletingLastPathComponent().appendingPathComponent("state.vscdb")
                        let stateDate = (try? FileSafety.fingerprint(state)).map { Date(timeIntervalSince1970: Double($0.seconds)) }
                        date = max(Date(timeIntervalSince1970: Double(fp.seconds)), stateDate ?? .distantPast)
                    } else { date = Date(timeIntervalSince1970: Double(fp.seconds)) }
                    let chunks = tool == .claude ? data.split(separator: 10).map { Data($0) } : [data]
                    for chunk in chunks { for path in paths(in: chunk) { add(tool: tool, path: path, date: date) } }
                }
                if let failure { throw failure }
            } catch { if !token.isCancelled { result.issues.append(ScanIssue(path: root.path, error: error)) } }
        }
        result.projects.sort { $0.path < $1.path }
        return result
    }
}
