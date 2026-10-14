import Foundation
import Darwin
import DonySystemBridge

public struct AgentTaskGroup: Identifiable, Sendable {
    public let root: ProcessReading
    public let tool: AITool
    public let workingDirectory: String
    public let members: [ProcessReading]
    public var id: String { root.id }
    public var memoryBytes: Int64 { members.reduce(0) { $0 + max(0, $1.memoryBytes) } }
    public init(root: ProcessReading, tool: AITool, workingDirectory: String, members: [ProcessReading]) {
        self.root = root; self.tool = tool; self.workingDirectory = workingDirectory; self.members = members
    }
}
public struct OwnedAgentTask: Identifiable, Codable, Sendable {
    public let root: ProcessReading
    public let tool: AITool
    public let workingDirectory: String
    public var members: [ProcessReading]
    public var id: String { root.id }
    public init(task: AgentTaskGroup, members: [ProcessReading]) {
        root = task.root; tool = task.tool; workingDirectory = task.workingDirectory; self.members = members
    }
}
public enum AgentTaskError: LocalizedError {
    case changed, unsafe, alreadyStopped, notOwned, partial(String)
    public var errorDescription: String? {
        switch self {
        case .changed: return "작업의 프로세스나 폴더가 변경됐습니다. 목록을 다시 확인해 주세요."
        case .unsafe: return "현재 앱·제어 호스트·보호된 프로세스 또는 확인되지 않은 작업은 제어할 수 없습니다."
        case .alreadyStopped: return "이미 정지된 프로세스가 있습니다. 도니홈이 정지한 작업만 재개할 수 있습니다."
        case .notOwned: return "도니홈이 일시 정지한 작업 기록이 없습니다."
        case let .partial(message): return message
        }
    }
}
public struct AgentTaskCallbacks: @unchecked Sendable {
    public let snapshot: () -> [ProcessReading]
    public let workingDirectory: (ProcessReading) -> String?
    public let rootTool: (ProcessReading) -> AITool?
    public let verifyIdentity: (ProcessReading) throws -> Void
    public let isStopped: (ProcessReading) -> Bool?
    public let signal: (Int32, Int32) throws -> Void
    public let persist: ([OwnedAgentTask]) throws -> Void
    public init(snapshot: @escaping () -> [ProcessReading], workingDirectory: @escaping (ProcessReading) -> String?, rootTool: @escaping (ProcessReading) -> AITool?, verifyIdentity: @escaping (ProcessReading) throws -> Void, isStopped: @escaping (ProcessReading) -> Bool?, signal: @escaping (Int32, Int32) throws -> Void, persist: @escaping ([OwnedAgentTask]) throws -> Void) {
        self.snapshot = snapshot; self.workingDirectory = workingDirectory; self.rootTool = rootTool; self.verifyIdentity = verifyIdentity; self.isStopped = isStopped; self.signal = signal; self.persist = persist
    }
    public static func live(store: URL) -> Self {
        Self(snapshot: { SystemSampler().sample().processes }, workingDirectory: { process in
            var buffer = [CChar](repeating: 0, count: 4096)
            guard dc_process_cwd(process.pid, &buffer, Int32(buffer.count)) != 0 else { return nil }
            return String(cString: buffer)
        }, rootTool: { process in
            var buffer = [CChar](repeating: 0, count: 8192)
            let length = dc_process_arguments(process.pid, &buffer, Int32(buffer.count))
            let arguments = length > 0 ? buffer.prefix(Int(length)).split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) } : []
            return AgentTaskControl.cliTool(process, arguments: arguments)
        }, verifyIdentity: ProcessPolicy.verifyIdentity, isStopped: { process in
            var info = proc_bsdinfo()
            guard proc_pidinfo(process.pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
                  info.pbi_uid == process.uid, info.pbi_start_tvsec == process.startSeconds, info.pbi_start_tvusec == process.startMicroseconds else { return nil }
            return info.pbi_status == 4 // BSD SSTOP; read-only and identity checked.
        }, signal: { pid, value in
            guard pid > 1 else { throw AgentTaskError.unsafe }
            guard Darwin.kill(pid, value) == 0 else { throw AgentTaskError.partial("프로세스 신호 요청 실패 · PID \(pid) · \(String(cString: strerror(errno)))") }
        }, persist: { records in
            let folder = store.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(records)
            try data.write(to: store, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.path)
        })
    }
}

/// Every signal is sent to one positive PID after a fresh graph and start-identity check.
/// Never uses a process group, negative PID, name-wide kill, or GUI-app termination.
public final class AgentTaskControl: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let callbacks: AgentTaskCallbacks
    private let currentUID: UInt32
    private let ownPID: Int32
    private var records: [OwnedAgentTask]
    public init(currentUID: UInt32, ownPID: Int32, callbacks: AgentTaskCallbacks, owned: [OwnedAgentTask] = []) {
        self.currentUID = currentUID; self.ownPID = ownPID; self.callbacks = callbacks
        let supported: Set<AITool> = [.codex, .claude, .hermes, .opencode, .gemini, .aider, .copilot, .cursor]
        records = owned.filter { record in
            record.root.uid == currentUID && record.root.pid > 1 && record.root.pid != ownPID && record.root.startSeconds > 0 && supported.contains(record.tool) && record.workingDirectory.hasPrefix("/") && !record.root.path.lowercased().contains(".app/") && !record.members.isEmpty && Set(record.members.map(\.id)).count == record.members.count && record.members.allSatisfy { $0.uid == currentUID && $0.pid > 1 && $0.startSeconds > 0 }
        }
    }
    public var ownedTasks: [OwnedAgentTask] { lock.lock(); defer { lock.unlock() }; return records }
    private static let direct: [String: AITool] = ["codex": .codex, "claude": .claude, "claude-code": .claude, "hermes": .hermes, "opencode": .opencode, "gemini": .gemini, "aider": .aider, "copilot": .copilot, "cursor-agent": .cursor]
    public static func cliTool(_ process: ProcessReading, arguments: [String] = []) -> AITool? {
        guard process.path.hasPrefix("/"), !process.path.lowercased().contains(".app/") else { return nil }
        let executable = URL(fileURLWithPath: process.path).lastPathComponent.lowercased()
        if let tool = direct[executable] { return process.toolHint == nil || process.toolHint == tool.rawValue ? tool : nil }
        guard ["node", "bun", "python", "python3", "ruby"].contains(executable) || executable.hasPrefix("python3."),
              arguments.count > 1, !arguments[1].hasPrefix("-"),
              let hint = process.toolHint.flatMap(AITool.init(rawValue:)) else { return nil }
        let script = arguments[1].lowercased()
        let filename = URL(fileURLWithPath: script).lastPathComponent
        let tool: AITool?
        if script.contains("/node_modules/@anthropic-ai/claude-code/") { tool = .claude }
        else if script.contains("/node_modules/@openai/codex/") { tool = .codex }
        else if script.contains("/node_modules/@google/gemini-cli/") { tool = .gemini }
        else { tool = direct[filename] }
        return tool == hint ? tool : nil
    }
    private static func descendants(_ pid: Int32, in rows: [ProcessReading]) -> Set<Int32> {
        var family: Set<Int32> = [pid]; var pending = [pid]
        while let current = pending.popLast() {
            for child in rows where child.parentPID == current && family.insert(child.pid).inserted { pending.append(child.pid) }
        }
        return family
    }
    private static func isControlHost(_ row: ProcessReading) -> Bool {
        let path = row.path.lowercased()
        return ["/codex.app/", "/chatgpt.app/", "/aside.app/"].contains(where: { path.contains($0) }) || (path.contains(".app/") && ["codex", "chatgpt", "aside"].contains(row.name.lowercased()))
    }
    private static func protectedWorkspacePaths(_ rows: [ProcessReading], ownPID: Int32, workingDirectory: (ProcessReading) -> String?) -> Set<String> {
        var hostFamily: Set<Int32> = [ownPID]
        for row in rows where isControlHost(row) { hostFamily.formUnion(descendants(row.pid, in: rows)) }
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL.path
        let broad = Set(["/", "/Users", "/Volumes", "/Applications", "/Library", "/System", "/usr", "/private", "/private/tmp", "/private/var", "/private/var/folders", home] + ["Documents", "Desktop", "Downloads", "Library", "Pictures", "Movies", "Music", "Public", "Projects", "Developer", "workspace", "workspaces"].map { home + "/" + $0 })
        return Set(rows.compactMap { row -> String? in
            guard hostFamily.contains(row.pid), let cwd = workingDirectory(row), cwd.hasPrefix("/") else { return nil }
            let path = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().standardizedFileURL.path
            var directory: ObjCBool = false
            guard !broad.contains(path), path.split(separator: "/").count >= 3, FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { return nil }
            return path
        })
    }
    private static func overlapsProtectedWorkspace(_ cwd: String?, protected: Set<String>) -> Bool {
        guard let cwd, cwd.hasPrefix("/") else { return true }
        let path = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().standardizedFileURL.path
        return protected.contains { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path == "/" ? "/" : path + "/") }
    }
    private static func protectedIDs(_ rows: [ProcessReading], ownPID: Int32) -> Set<Int32> {
        let byPID = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var result = descendants(ownPID, in: rows)
        var pid = ownPID; var seen = Set<Int32>()
        while seen.insert(pid).inserted, let row = byPID[pid] { result.insert(pid); pid = row.parentPID }
        for row in rows {
            if isControlHost(row) {
                result.formUnion(descendants(row.pid, in: rows))
                var ancestor = row.parentPID; var visited = Set<Int32>()
                while visited.insert(ancestor).inserted, let parent = byPID[ancestor] { result.insert(ancestor); ancestor = parent.parentPID }
            }
        }
        return result
    }
    private static func safe(_ process: ProcessReading, uid: UInt32, excluded: Set<Int32>) -> Bool {
        let name = process.name.lowercased(); let executable = URL(fileURLWithPath: process.path).lastPathComponent.lowercased()
        let containers: Set<String> = ["terminal", "iterm", "iterm2", "warp", "ghostty", "wezterm", "alacritty", "kitty", "tmux", "cmux", "orca", "herdr", "herdr-server", "chatgpt", "aside"]
        return process.pid > 1 && process.uid == uid && process.startSeconds > 0 && process.startMicroseconds < 1_000_000 && !excluded.contains(process.pid) && !ProcessPolicy.protectedNames.contains(process.name) && !containers.contains(name) && !containers.contains(executable) && !name.hasPrefix("tmux:") && !process.path.lowercased().contains(".app/") && process.path.hasPrefix("/")
    }
    public static func discover(_ rows: [ProcessReading], currentUID: UInt32, ownPID: Int32, workingDirectory: (ProcessReading) -> String?, rootTool: (ProcessReading) -> AITool?) -> [AgentTaskGroup] {
        let excluded = protectedIDs(rows, ownPID: ownPID)
        let protectedPaths = protectedWorkspacePaths(rows, ownPID: ownPID, workingDirectory: workingDirectory)
        let candidates = rows.filter { safe($0, uid: currentUID, excluded: excluded) && rootTool($0) != nil }
        let candidateIDs = Set(candidates.map(\.pid))
        let byPID = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return candidates.compactMap { root in
            var ancestor = root.parentPID; var seen: Set<Int32> = [root.pid]
            while let row = byPID[ancestor] {
                guard seen.insert(ancestor).inserted, !candidateIDs.contains(ancestor) else { return nil }
                ancestor = row.parentPID
            }
            let ids = descendants(root.pid, in: rows)
            let members = rows.filter { ids.contains($0.pid) }.sorted { $0.pid == root.pid ? true : $1.pid == root.pid ? false : $0.pid < $1.pid }
            guard let cwd = workingDirectory(root), cwd.hasPrefix("/"), !overlapsProtectedWorkspace(cwd, protected: protectedPaths), let tool = rootTool(root),
                  members.allSatisfy({ safe($0, uid: currentUID, excluded: excluded) && workingDirectory($0)?.hasPrefix("/") == true && !overlapsProtectedWorkspace(workingDirectory($0), protected: protectedPaths) }) else { return nil }
            return AgentTaskGroup(root: root, tool: tool, workingDirectory: cwd, members: members)
        }.sorted { $0.memoryBytes > $1.memoryBytes }
    }
    private func refreshed(_ task: AgentTaskGroup, allowMissing: Bool = false) throws -> [ProcessReading] {
        let rows = callbacks.snapshot()
        let excluded = Self.protectedIDs(rows, ownPID: ownPID)
        let protectedPaths = Self.protectedWorkspacePaths(rows, ownPID: ownPID, workingDirectory: callbacks.workingDirectory)
        guard !Self.overlapsProtectedWorkspace(task.workingDirectory, protected: protectedPaths) else { throw AgentTaskError.unsafe }
        guard let root = rows.first(where: { ProcessPolicy.sameIdentity($0, task.root) }),
              Self.safe(root, uid: currentUID, excluded: excluded), callbacks.rootTool(root) == task.tool,
              callbacks.workingDirectory(root) == task.workingDirectory else { throw AgentTaskError.changed }
        let family = Self.descendants(root.pid, in: rows)
        let expected = Set(task.members.map(\.pid))
        guard expected.count == task.members.count, task.members.contains(where: { ProcessPolicy.sameIdentity($0, task.root) }) else { throw AgentTaskError.unsafe }
        guard family.isSubset(of: expected), allowMissing || family == expected else { throw AgentTaskError.changed }
        let current = rows.filter { family.contains($0.pid) }
        guard current.allSatisfy({ row in task.members.contains { ProcessPolicy.sameIdentity($0, row) } && Self.safe(row, uid: currentUID, excluded: excluded) && callbacks.workingDirectory(row)?.hasPrefix("/") == true && !Self.overlapsProtectedWorkspace(callbacks.workingDirectory(row), protected: protectedPaths) }) else { throw AgentTaskError.unsafe }
        return current
    }
    private func signal(_ original: ProcessReading, value: Int32) throws {
        let rows = callbacks.snapshot()
        let excluded = Self.protectedIDs(rows, ownPID: ownPID)
        guard let current = rows.first(where: { ProcessPolicy.sameIdentity($0, original) }), Self.safe(current, uid: currentUID, excluded: excluded) else { throw AgentTaskError.changed }
        if value == SIGCONT {
            // Undo only our successful STOP requests, even when cwd disappears or
            // an active host subsequently starts using that folder.
            guard records.contains(where: { $0.members.contains { ProcessPolicy.sameIdentity($0, original) } }) else { throw AgentTaskError.notOwned }
        } else {
            let protectedPaths = Self.protectedWorkspacePaths(rows, ownPID: ownPID, workingDirectory: callbacks.workingDirectory)
            guard let cwd = callbacks.workingDirectory(current), cwd.hasPrefix("/"), !Self.overlapsProtectedWorkspace(cwd, protected: protectedPaths) else { throw AgentTaskError.unsafe }
        }
        try callbacks.verifyIdentity(current)
        try callbacks.signal(current.pid, value)
    }
    private func save() throws { try callbacks.persist(records) }
    private func store(_ task: AgentTaskGroup, stopped: [ProcessReading]) {
        records.removeAll { $0.id == task.id }
        if !stopped.isEmpty { records.append(OwnedAgentTask(task: task, members: stopped)) }
    }
    public func pause(_ task: AgentTaskGroup) throws {
        lock.lock(); defer { lock.unlock() }
        guard !records.contains(where: { $0.id == task.id }) else { throw AgentTaskError.alreadyStopped }
        let initial = try refreshed(task)
        guard initial.allSatisfy({ callbacks.isStopped($0) == false }) else { throw AgentTaskError.alreadyStopped }
        var stopped: [ProcessReading] = []
        do {
            let ordered = task.members.sorted { $0.pid == task.root.pid ? true : $1.pid == task.root.pid ? false : $0.pid < $1.pid }
            for member in ordered {
                _ = try refreshed(task)
                guard callbacks.isStopped(member) == false else { throw AgentTaskError.alreadyStopped }
                try signal(member, value: SIGSTOP)
                stopped.append(member); store(task, stopped: stopped); try save()
            }
        } catch {
            let failure = error
            for member in stopped.reversed() {
                do { try signal(member, value: SIGCONT); stopped.removeAll { ProcessPolicy.sameIdentity($0, member) } } catch { /* retain exact ownership for manual recovery */ }
            }
            store(task, stopped: stopped); try? save()
            throw AgentTaskError.partial("일시 정지 요청을 완료하지 못했습니다. \(stopped.isEmpty ? "이미 정지한 프로세스는 재개했습니다." : "재개하지 못한 프로세스는 복구 목록에 보관했습니다.") \(failure.localizedDescription)")
        }
    }
    @discardableResult public func resume(id: String) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw AgentTaskError.notOwned }
        let record = records[index]
        let rows = callbacks.snapshot(); let excluded = Self.protectedIDs(rows, ownPID: ownPID)
        let matching = record.members.compactMap { original in rows.first { ProcessPolicy.sameIdentity($0, original) } }
        guard matching.allSatisfy({ Self.safe($0, uid: currentUID, excluded: excluded) }) else { throw AgentTaskError.unsafe }
        var remaining = matching; var count = 0
        // Children first, root last: the root cannot spawn workers before recovery finishes.
        for member in matching.reversed() {
            do { try signal(member, value: SIGCONT); remaining.removeAll { ProcessPolicy.sameIdentity($0, member) }; count += 1 }
            catch { records[index].members = remaining; try? save(); throw error }
            records[index].members = remaining; try save()
        }
        records.removeAll { $0.id == id }; try save()
        return count
    }
    @discardableResult public func stop(_ task: AgentTaskGroup) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let initial = try refreshed(task)
        let owned = records.first { $0.id == task.id }
        guard initial.allSatisfy({ row in callbacks.isStopped(row) == false || owned?.members.contains(where: { ProcessPolicy.sameIdentity($0, row) }) == true }) else { throw AgentTaskError.alreadyStopped }
        var count = 0
        for member in task.members.reversed() {
            _ = try refreshed(task, allowMissing: true)
            let live = callbacks.snapshot().contains { ProcessPolicy.sameIdentity($0, member) }
            guard live else { continue }
            try signal(member, value: SIGTERM); count += 1
            if owned?.members.contains(where: { ProcessPolicy.sameIdentity($0, member) }) == true {
                // Deliver queued SIGTERM without ever resuming externally stopped processes.
                try signal(member, value: SIGCONT)
                if let index = records.firstIndex(where: { $0.id == task.id }) {
                    records[index].members.removeAll { ProcessPolicy.sameIdentity($0, member) }; try save()
                }
            }
        }
        records.removeAll { $0.id == task.id }; try save()
        return count
    }
}
