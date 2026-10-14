import Foundation
import Darwin

/// File-backed output lets a foreground command return even when a detached child
/// inherits stderr. Time limits are suitable for status/probe commands, not calibration.
public enum BatteryCommandRunner {
    public static func run(_ executable: String, arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval? = nil) throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("donyhome-battery-" + UUID().uuidString + ".log")
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw BatteryError.failed("배터리 명령의 임시 출력 파일을 만들지 못했습니다.")
        }
        let output = try FileHandle(forWritingTo: file)
        defer { try? output.close(); try? FileManager.default.removeItem(at: file) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = output; process.standardInput = FileHandle.nullDevice
        process.environment = environment
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        if let timeout {
            guard timeout.isFinite, timeout > 0 else { process.terminate(); throw BatteryError.failed("잘못된 명령 제한 시간입니다.") }
            if ended.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                if ended.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
                throw BatteryError.failed("배터리 상태 확인 시간이 초과되었습니다.")
            }
        } else { ended.wait() }
        let reader = try FileHandle(forReadingFrom: file); defer { try? reader.close() }
        let count = try reader.seekToEnd()
        try reader.seek(toOffset: count > 12000 ? count - 12000 : 0)
        let text = String(decoding: try reader.readToEnd() ?? Data(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw BatteryError.failed(text.isEmpty ? "배터리 명령이 종료되었습니다 (\(process.terminationStatus))." : text)
        }
        return text
    }
}
