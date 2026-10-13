import Foundation
import DonySystemBridge

public struct RuntimeDiscovery: Sendable {
    public var projects: [LinkedProject] = []
    public var statuses: [AITool: String] = [:]
}
public enum DevelopmentRuntime {
    public static func projectRoot(forWorkingDirectory path: String) -> URL? {
        var folder = URL(fileURLWithPath: path)
        for _ in 0..<8 {
            if let root = try? ProjectCleanup.projectRoot(folder.path) { return root }
            guard folder.path != "/" else { break }; folder.deleteLastPathComponent()
        }
        return nil
    }
    public static func runningProjects(processes: [ProcessReading], currentUID: UInt32, applicationTools: [String: AITool], tools: Set<AITool>) -> [LinkedProject] {
        let assigned = AITool.assignments(processes, currentUID: currentUID, applicationTools: applicationTools)
        var projects: [LinkedProject] = []
        for process in processes where process.uid == currentUID {
            guard let tool = assigned[process.pid], tools.contains(tool) else { continue }
            var buffer = [CChar](repeating: 0, count: 4096)
            let found = buffer.withUnsafeMutableBufferPointer { dc_process_cwd(process.pid, $0.baseAddress, Int32($0.count)) }
            guard found != 0, let root = projectRoot(forWorkingDirectory: String(cString: buffer)) else { continue }
            let project = LinkedProject(tool: tool, path: root.path, lastActivity: Date(), enabled: false, discovered: true)
            if !projects.contains(where: { $0.id == project.id }) { projects.append(project) }
        }
        return projects
    }
    public static func link(projectPaths: [String], tools: Set<AITool>, existing: [LinkedProject]) -> [LinkedProject] {
        var result = existing
        for path in projectPaths {
            for tool in tools.sorted(by: { $0.rawValue < $1.rawValue }) {
                let link = LinkedProject(tool: tool, path: path)
                if !result.contains(where: { $0.id == link.id }) { result.append(link) }
            }
        }
        return result
    }
    public static func executable(for tool: AITool, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init) + [home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".cargo/bin").path, home.appendingPathComponent(".bun/bin").path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/Applications/cmux.app/Contents/Resources/bin"]
        for directory in directories {
            for name in tool.executableNames where !name.contains(" ") {
                let file = URL(fileURLWithPath: directory).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: file.path) { return file }
            }
        }
        return nil
    }
    public static func installed(_ tool: AITool, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        if executable(for: tool, home: home) != nil { return true }
        return ([tool.title] + tool.executableNames).contains { name in
            ["/Applications/", home.appendingPathComponent("Applications").path + "/"].contains { FileManager.default.fileExists(atPath: $0 + name + ".app") }
        }
    }
    public static func paths(in data: Data) -> [String] {
        guard data.count <= 2_000_000, let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var found = Set<String>(); var count = 0
        func walk(_ value: Any, depth: Int) {
            guard depth < 16, count < 10_000 else { return }; count += 1
            if let object = value as? [String: Any] {
                if object["remote"] as? Bool == true { return }
                if let machine = object["machine"] as? String, !["local", "localhost"].contains(machine) { return }
                if let host = object["hostKind"] as? String, host != "local" { return }
                if let host = object["hostId"] as? String, host != "local" { return }
                if let host = object["executionHostId"] as? String, host != "local" { return }
                if let platform = object["terminalPlatform"] as? String, platform != "darwin" { return }
                for key in ["cwd", "foreground_cwd", "workingDirectory", "worktreePath", "repoPath"] {
                    if let path = object[key] as? String, path.hasPrefix("/") { found.insert(path) }
                }
                // Orca worktree ps returns a structured worktree record with path, not cwd.
                if object["worktreeId"] as? String != nil, let path = object["path"] as? String, path.hasPrefix("/") { found.insert(path) }
                for key in ["result", "data", "workspaces", "worktrees", "projects", "panes", "tabs", "agents", "repositories", "children"] {
                    if let child = object[key] { walk(child, depth: depth + 1) }
                }
            } else if let array = value as? [Any] { for child in array.prefix(2000) { walk(child, depth: depth + 1) } }
        }
        walk(json, depth: 0); return found.sorted()
    }
    public static func tmuxPaths(_ output: String) -> [String] {
        output.split(separator: "\n").compactMap { row in
            let fields = row.split(separator: "\t", maxSplits: 1)
            return fields.count == 2 && Int32(fields[0]) != nil && fields[1].hasPrefix("/") ? String(fields[1]) : nil
        }
    }
    public static func metadataPaths(_ output: String, tool: AITool) -> [String]? {
        if tool == .tmux {
            let found = tmuxPaths(output)
            return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !found.isEmpty ? found : nil
        }
        let data = Data(output.utf8)
        guard let json = try? JSONSerialization.jsonObject(with: data), json is [String: Any] || json is [Any] else { return nil }
        if let object = json as? [String: Any] {
            guard object["error"] == nil, object["success"] as? Bool != false,
                  !Set(object.keys).isDisjoint(with: ["result", "data", "worktrees", "workspaces", "panes", "tabs", "agents", "repositories", "cwd"]) else { return nil }
        }
        return paths(in: data)
    }
    public static func discover(tools: Set<AITool>, token: ScanToken) -> RuntimeDiscovery {
        var result = RuntimeDiscovery()
        let commands: [(AITool, [String])] = [(.herdr, ["api", "snapshot"]), (.orca, ["worktree", "ps", "--json"]), (.cmux, ["list-workspaces", "--json"]), (.tmux, ["list-panes", "-a", "-F", "#{pane_pid}\t#{pane_current_path}"])]
        for (tool, args) in commands where tools.contains(tool) {
            if token.isCancelled { break }
            guard let executable = executable(for: tool) else { result.statuses[tool] = "CLI 연결 필요"; continue }
            do {
                let command = try CommandRunner.run(CommandSpec(executable: executable.path, arguments: args, requiresAdmin: false), timeout: 3)
                guard command.success else { result.statuses[tool] = "실행 또는 연결 확인"; continue }
                guard let paths = metadataPaths(command.output, tool: tool) else { result.statuses[tool] = "응답 확인 필요"; continue }
                for path in paths {
                    if let root = try? ProjectCleanup.projectRoot(path) {
                        result.projects.append(LinkedProject(tool: tool, path: root.path, lastActivity: Date(), enabled: false, discovered: true))
                    }
                }
                result.statuses[tool] = "연결됨"
            } catch { result.statuses[tool] = "연결 확인 필요" }
        }
        return result
    }
}
