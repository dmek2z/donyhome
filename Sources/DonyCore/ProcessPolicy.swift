import Foundation
import DonySystemBridge
public enum ProcessPolicy {
    public static let protectedNames: Set<String> = ["kernel_task", "launchd", "loginwindow", "WindowServer", "Dock", "Finder", "SystemUIServer", "ControlCenter", "NotificationCenter", "securityd", "DonyClean", "DonyHome", "donyhome"]
    public static func canQuit(_ process: ProcessReading, currentUID: UInt32, ownPID: Int32, regularApplication: Bool) -> Bool {
        process.pid > 1 && process.pid != ownPID && process.uid == currentUID && regularApplication && !protectedNames.contains(process.name)
    }
    public static func sameIdentity(_ a: ProcessReading, _ b: ProcessReading) -> Bool { a.pid == b.pid && a.uid == b.uid && a.startSeconds == b.startSeconds && a.startMicroseconds == b.startMicroseconds }
    public static func verifyIdentity(_ process: ProcessReading) throws {
        guard dc_process_matches(process.pid, process.uid, process.startSeconds, process.startMicroseconds) != 0 else { throw DonyError.processChanged }
    }
}

/// GUI 앱이 아닌 개발용 CLI 프로세스 중 폭주하거나 방치된 것을 찾는다. 종료는 사용자가 확인한 뒤 일반 종료(SIGTERM)만 보낸다.
public enum CLIProcessPolicy {
    public static let protectedNames: Set<String> = ["claude", "zsh", "bash", "fish", "sh", "login", "tmux", "screen", "ssh", "sshd", "sudo", "su", "launchd", "caffeinate"]
    static let systemPrefixes = ["/System/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/sbin/", "/bin/", "/Library/", "/private/"]
    public static let runawayCPU = 50.0
    public static let runawayMinutes = 10.0
    public static let idleMemory: Int64 = 300_000_000
    public static let idleHours = 6.0

    public struct Finding: Identifiable, Sendable {
        public var id: String { process.id }
        public let process: ProcessReading
        public let reason: String
    }

    public static func isEligible(_ process: ProcessReading, currentUID: UInt32, ownPID: Int32) -> Bool {
        process.pid > 1 && process.pid != ownPID && process.uid == currentUID
            && !ProcessPolicy.protectedNames.contains(process.name) && !protectedNames.contains(process.name)
            && !process.path.isEmpty && !process.path.contains(".app/")
            && !systemPrefixes.contains { process.path.hasPrefix($0) }
    }

    public static func findings(_ processes: [ProcessReading], currentUID: UInt32, ownPID: Int32, now: Date = Date()) -> [Finding] {
        processes.compactMap { process -> Finding? in
            guard isEligible(process, currentUID: currentUID, ownPID: ownPID) else { return nil }
            let minutes = now.timeIntervalSince1970 - Double(process.startSeconds)
            let age = minutes / 60
            if let cpu = process.cpuPercent, cpu >= runawayCPU, age >= runawayMinutes {
                return Finding(process: process, reason: "CPU \(Int(cpu))% · \(duration(age))째 실행 중")
            }
            if process.memoryBytes >= idleMemory, (process.cpuPercent ?? 100) < 1, age >= idleHours * 60 {
                return Finding(process: process, reason: "\(DisplayFormat.bytes(process.memoryBytes)) 차지 · \(duration(age))째 유휴")
            }
            return nil
        }.sorted { ($0.process.cpuPercent ?? 0, $0.process.memoryBytes) > ($1.process.cpuPercent ?? 0, $1.process.memoryBytes) }
    }

    static func duration(_ minutes: Double) -> String {
        minutes >= 120 ? "\(Int(minutes / 60))시간" : "\(Int(minutes))분"
    }
}
