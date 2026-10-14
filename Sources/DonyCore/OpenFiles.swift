import Foundation
import DonySystemBridge

public struct OpenFileSnapshot: Sendable {
    public let paths: Set<String>
    public let identities: Set<String>
    public let complete: Bool
    public init(paths: Set<String>, identities: Set<String> = [], complete: Bool) {
        self.paths = paths; self.identities = identities; self.complete = complete
    }
    public func contains(_ candidate: FileCandidate) -> Bool {
        paths.contains(candidate.id) || identities.contains(candidate.fingerprint.identity)
    }
    static func isProtectedPlatformProcess(_ path: String) -> Bool {
        ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }
    public static func read(processes: [ProcessReading], token: ScanToken, enumerationComplete: Bool = false) -> Self {
        guard enumerationComplete, !processes.isEmpty else { return Self(paths: [], complete: false) }
        var paths = Set<String>(); var identities = Set<String>(); var seen = Set<Int32>()
        var buffer = [CChar](repeating: 0, count: 2_000_000)
        for process in processes where seen.insert(process.pid).inserted {
            guard !token.isCancelled else { return Self(paths: paths, identities: identities, complete: false) }
            // 목록을 읽은 뒤 끝난 프로세스는 더 이상 파일을 잡을 수 없으므로 건너뛴다.
            guard dc_process_matches(process.pid, process.uid, process.startSeconds, process.startMicroseconds) != 0 else { continue }
            let count = buffer.withUnsafeMutableBufferPointer { dc_process_open_files(process.pid, $0.baseAddress, Int32($0.count)) }
            guard !token.isCancelled else { return Self(paths: paths, identities: identities, complete: false) }
            // 읽는 도중 프로세스가 끝났다면(또는 같은 PID가 재사용됐다면) 이 프로세스의 결과는 쓰지 않고 건너뛴다.
            guard dc_process_matches(process.pid, process.uid, process.startSeconds, process.startMicroseconds) != 0 else { continue }
            guard count >= 0 else {
                // macOS가 열린 파일 목록을 막아 둔 Apple 시스템 에이전트는 서드파티 도구의 캐시·로그를 잡지 않으므로 건너뛴다.
                if Self.isProtectedPlatformProcess(process.path) { continue }
                return Self(paths: paths, identities: identities, complete: false)
            }
            var record = [UInt8]()
            for character in buffer.prefix(Int(count)) {
                let byte = UInt8(bitPattern: character)
                if byte != 0 { record.append(byte); continue }
                guard let value = String(bytes: record, encoding: .utf8), value.count > 1 else { return Self(paths: paths, identities: identities, complete: false) }
                if value.first == "p" { paths.insert(String(value.dropFirst())) }
                else if value.first == "i" { identities.insert(String(value.dropFirst())) }
                else { return Self(paths: paths, identities: identities, complete: false) }
                record.removeAll(keepingCapacity: true)
            }
            guard record.isEmpty else { return Self(paths: paths, identities: identities, complete: false) }
        }
        return Self(paths: paths, identities: identities, complete: !token.isCancelled)
    }
}

/// Separate from the display sampler: no 4,096-row limit or silently skipped
/// helpers may certify an inactive owner or a closed log.
public struct OwnedProcessInventory: Sendable {
    public let processes: [ProcessReading]
    public let complete: Bool
    public static func read(capacity requested: Int? = nil) -> Self {
        let capacity = requested ?? Int(dc_owned_process_capacity())
        guard (1...16_384).contains(capacity) else { return Self(processes: [], complete: false) }
        var rows = Array(repeating: DCProcess(), count: capacity)
        var complete: Int32 = 0
        let count = rows.withUnsafeMutableBufferPointer { dc_read_owned_processes($0.baseAddress, Int32($0.count), &complete) }
        let processes = (0..<max(0, Int(count))).map { i -> ProcessReading in
            var row = rows[i]
            let name = withUnsafePointer(to: &row.name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
            let path = withUnsafePointer(to: &row.path) { $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) } }
            var hint: String?
            if AITool.isInterpreter(name) {
                var args = [CChar](repeating: 0, count: 8192)
                let length = args.withUnsafeMutableBufferPointer { dc_process_arguments(row.pid, $0.baseAddress, Int32($0.count)) }
                if length > 0 {
                    let values = args.prefix(Int(length)).split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
                    hint = AITool.commandHint(values)?.rawValue
                }
            }
            return ProcessReading(pid: row.pid, uid: row.uid, startSeconds: row.start_seconds, startMicroseconds: row.start_microseconds, name: name, path: path, memoryBytes: -1, cpuNanos: nil, cpuPercent: nil, parentPID: row.parent_pid, toolHint: hint)
        }
        return Self(processes: processes, complete: complete != 0)
    }
    public func openFiles(token: ScanToken) -> OpenFileSnapshot {
        // 프로세스가 계속 생기고 끝나는 Mac(AI 도구 등)에서는 두 번 읽은 목록이 같기를 기다리면 영영 확정되지 않는다.
        // 끝난 프로세스는 건너뛰고, 새로 생긴 프로세스는 직접 읽어서 합친다. 그래도 실패하면 최대 4번 다시 시도한다.
        var current = self
        for _ in 0..<4 {
            guard !token.isCancelled else { break }
            let files = OpenFileSnapshot.read(processes: current.processes, token: token, enumerationComplete: current.complete)
            let after = Self.read()
            let known = Set(current.processes.map(\.id))
            let newcomers = after.processes.filter { !known.contains($0.id) }
            var paths = files.paths, identities = files.identities
            var ok = files.complete && after.complete
            if ok, !newcomers.isEmpty {
                let extra = OpenFileSnapshot.read(processes: newcomers, token: token, enumerationComplete: true)
                paths.formUnion(extra.paths); identities.formUnion(extra.identities); ok = extra.complete
            }
            if ok { return OpenFileSnapshot(paths: paths, identities: identities, complete: !token.isCancelled) }
            current = after
        }
        return OpenFileSnapshot(paths: [], identities: [], complete: false)
    }
}
