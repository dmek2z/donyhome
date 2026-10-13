import Foundation

public enum MaintenanceTask: Sendable {
    case flushDNS, reindexSpotlight, deleteSnapshot(String)
    public var title: String {
        switch self { case .flushDNS: return "DNS 캐시 초기화"; case .reindexSpotlight: return "Spotlight 재색인"; case .deleteSnapshot(let date): return "로컬 스냅샷 제거 · " + date }
    }
}
public struct CommandSpec: Sendable {
    public let executable: String
    public let arguments: [String]
    public let requiresAdmin: Bool
}
public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    public var success: Bool { status == 0 }
    public init(status: Int32, output: String) { self.status = status; self.output = output }
}
public enum Maintenance {
    private static func validDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd-HHmmss"; formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }
    public static func snapshots(from output: String) -> [String] {
        Array(Set(output.split(separator: "\n").compactMap { line in
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "com.apple.TimeMachine."
            guard text.hasPrefix(prefix), text.hasSuffix(".local") else { return nil }
            let date = String(text.dropFirst(prefix.count).dropLast(6))
            return validDate(date) ? date : nil
        })).sorted(by: >)
    }
    public static func commands(for task: MaintenanceTask) throws -> [CommandSpec] {
        switch task {
        case .flushDNS: return [CommandSpec(executable: "/usr/bin/dscacheutil", arguments: ["-flushcache"], requiresAdmin: true), CommandSpec(executable: "/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"], requiresAdmin: true)]
        case .reindexSpotlight: return [CommandSpec(executable: "/usr/bin/mdutil", arguments: ["-E", "/"], requiresAdmin: true)]
        case .deleteSnapshot(let date):
            guard validDate(date) else { throw DonyError.unsafePath }
            return [CommandSpec(executable: "/usr/bin/tmutil", arguments: ["deletelocalsnapshots", date], requiresAdmin: true)]
        }
    }
    public static func execute(_ task: MaintenanceTask, run: (CommandSpec) throws -> CommandResult) throws -> CommandResult {
        var output: [String] = []
        for command in try commands(for: task) {
            let result = try run(command); output.append(result.output)
            if !result.success { return CommandResult(status: result.status, output: output.joined(separator: "\n")) }
        }
        return CommandResult(status: 0, output: output.joined(separator: "\n"))
    }
    public static func listSnapshots() throws -> [String] {
        let result = try CommandRunner.run(CommandSpec(executable: "/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"], requiresAdmin: false))
        guard result.success else { throw NSError(domain: "DonyClean", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: result.output]) }
        return snapshots(from: result.output)
    }
}
public enum CommandRunner {
    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    /// Only callers in Maintenance construct these fixed commands; no user shell input.
    public static func run(_ spec: CommandSpec, timeout: TimeInterval = 60) throws -> CommandResult {
        let process = Process()
        if spec.requiresAdmin {
            let shell = ([spec.executable] + spec.arguments).map(quote).joined(separator: " ")
            let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"" + escaped + "\" with administrator privileges"]
        } else { process.executableURL = URL(fileURLWithPath: spec.executable); process.arguments = spec.arguments }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("DonyClean-command-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw DonyError.unsupported }
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return CommandResult(status: -1, output: "작업 대기 시간이 초과됐습니다. 시스템 인증 창과 작업 상태를 확인해 주세요.") }
        let data = try Data(contentsOf: log)
        let text = String(decoding: data.prefix(65_536), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(status: process.terminationStatus, output: text)
    }
}
