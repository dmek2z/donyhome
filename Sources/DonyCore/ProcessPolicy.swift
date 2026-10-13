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
