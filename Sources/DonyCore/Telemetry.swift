import Foundation
import Darwin
import DonySystemBridge

public struct CPUCounters: Sendable {
    public let user, system, idle, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) { self.user = user; self.system = system; self.idle = idle; self.nice = nice }
    public func usage(since previous: Self) -> Double? {
        guard user >= previous.user, system >= previous.system, idle >= previous.idle, nice >= previous.nice else { return nil }
        let active = Double(user - previous.user) + Double(system - previous.system) + Double(nice - previous.nice)
        let total = active + Double(idle - previous.idle)
        return total > 0 ? min(100, max(0, 100 * active / total)) : nil
    }
}
public enum ProcessCPU {
    public static func nanoseconds(ticks: UInt64, numerator: UInt32, denominator: UInt32) -> UInt64? {
        guard numerator > 0, denominator > 0 else { return nil }
        let quotient = ticks / UInt64(denominator)
        let remainder = ticks % UInt64(denominator)
        let (whole, overflow) = quotient.multipliedReportingOverflow(by: UInt64(numerator))
        guard !overflow else { return nil }
        let fraction = remainder * UInt64(numerator) / UInt64(denominator)
        let (result, additionOverflow) = whole.addingReportingOverflow(fraction)
        return additionOverflow ? nil : result
    }
    public static func usage(currentNanos: UInt64, previousNanos: UInt64, elapsed: Double) -> Double? {
        guard elapsed > 0, currentNanos >= previousNanos else { return nil }
        return Double(currentNanos - previousNanos) / 1_000_000_000 / elapsed * 100
    }
}
public enum MemoryPressure: String, Codable, Sendable {
    case normal, warning, critical, unknown
    public var label: String { switch self { case .normal: return "여유"; case .warning: return "주의"; case .critical: return "부족"; case .unknown: return "측정 불가" } }
}
public struct ProcessReading: Identifiable, Codable, Sendable {
    public var id: String { "\(pid):\(startSeconds):\(startMicroseconds)" }
    public let pid: Int32
    public let parentPID: Int32
    public let toolHint: String?
    public let uid: UInt32
    public let startSeconds, startMicroseconds: UInt64
    public let name, path: String
    public let memoryBytes: Int64
    public let cpuNanos: UInt64?
    public let cpuPercent: Double?
    public init(pid: Int32, uid: UInt32, startSeconds: UInt64, startMicroseconds: UInt64, name: String, path: String, memoryBytes: Int64, cpuNanos: UInt64?, cpuPercent: Double?, parentPID: Int32 = 0, toolHint: String? = nil) {
        self.pid = pid; self.parentPID = parentPID; self.toolHint = toolHint; self.uid = uid; self.startSeconds = startSeconds; self.startMicroseconds = startMicroseconds
        self.name = name; self.path = path; self.memoryBytes = memoryBytes; self.cpuNanos = cpuNanos; self.cpuPercent = cpuPercent
    }
    public var memoryLabel: String { memoryBytes >= 0 ? DisplayFormat.bytes(memoryBytes) : "—" }
}
public struct SystemSnapshot: Codable, Sendable {
    public var timestamp = Date()
    public var cpuPercent: Double?
    public var memoryTotal: Int64 = 0
    public var memoryUsed: Int64?
    public var memoryCached: Int64?
    public var memoryCompressed: Int64?
    public var swapUsed: Int64?
    public var pressure: MemoryPressure = .unknown
    public var diskTotal: Int64?
    public var diskAvailable: Int64?
    public var battery: BatteryReading?
    public var networkReceivedPerSecond: Double?
    public var networkSentPerSecond: Double?
    public var processes: [ProcessReading] = []
    public var memoryPercent: Double? { guard let memoryUsed, memoryTotal > 0 else { return nil }; return Double(memoryUsed) / Double(memoryTotal) * 100 }
    public init() {}
}
public final class SystemSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousNetwork: NetworkCounters?
    private var previousCPU: CPUCounters?
    private var previousProcesses: [String: UInt64] = [:]
    private var previousTime: Double?
    private var toolHints: [String: String] = [:]
    private var timebase = mach_timebase_info_data_t()
    public init() { _ = mach_timebase_info(&timebase) }
    public func sample() -> SystemSnapshot {
        lock.lock(); defer { lock.unlock() }
        var raw = DCSystem(); _ = dc_read_system(&raw)
        let now = ProcessInfo.processInfo.systemUptime
        var snapshot = SystemSnapshot()
        snapshot.battery = BatteryReading.read()
        var network = DCNetwork(); _ = dc_read_network(&network)
        if network.available != 0 {
            let current = NetworkCounters(received: network.received, sent: network.sent, generation: network.generation)
            if let previousNetwork, let previousTime, let rate = current.rates(since: previousNetwork, elapsed: now - previousTime) {
                snapshot.networkReceivedPerSecond = rate.received; snapshot.networkSentPerSecond = rate.sent
            }
            previousNetwork = current
        } else { previousNetwork = nil }
        let cpu = CPUCounters(user: raw.cpu_user, system: raw.cpu_system, idle: raw.cpu_idle, nice: raw.cpu_nice)
        if raw.cpu_available != 0 { if let previousCPU { snapshot.cpuPercent = cpu.usage(since: previousCPU) }; previousCPU = cpu }
        else { previousCPU = nil }
        snapshot.memoryTotal = Int64(raw.memory_total)
        if raw.memory_available != 0 { snapshot.memoryUsed = Int64(raw.memory_used); snapshot.memoryCached = Int64(raw.memory_cached); snapshot.memoryCompressed = Int64(raw.memory_compressed) }
        if raw.swap_available != 0 { snapshot.swapUsed = Int64(raw.swap_used) }
        switch raw.pressure { case 1: snapshot.pressure = .normal; case 2: snapshot.pressure = .warning; case 4: snapshot.pressure = .critical; default: break }
        if let disk = try? FileManager.default.attributesOfFileSystem(forPath: FileManager.default.homeDirectoryForCurrentUser.path) {
            snapshot.diskTotal = (disk[.systemSize] as? NSNumber)?.int64Value; snapshot.diskAvailable = (disk[.systemFreeSize] as? NSNumber)?.int64Value
        }
        var rows = Array(repeating: DCProcess(), count: 4096)
        let count = rows.withUnsafeMutableBufferPointer { dc_read_processes($0.baseAddress, Int32($0.count)) }
        var newCounters: [String: UInt64] = [:]
        var newHints: [String: String] = [:]
        for index in 0..<max(0, Int(count)) {
            var row = rows[index]
            let name = withUnsafePointer(to: &row.name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
            let path = withUnsafePointer(to: &row.path) { $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) } }
            let key = "\(row.pid):\(row.start_seconds):\(row.start_microseconds)"
            var hint = toolHints[key]
            if hint == nil && row.uid == getuid() && AITool.isInterpreter(name) {
                var args = [CChar](repeating: 0, count: 8192)
                let length = args.withUnsafeMutableBufferPointer { dc_process_arguments(row.pid, $0.baseAddress, Int32($0.count)) }
                if length > 0 {
                    let values = args.prefix(Int(length)).split(separator: 0).map { bytes in String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
                    hint = AITool.commandHint(values)?.rawValue
                }
            }
            if let hint { newHints[key] = hint }
            var percent: Double?
            let nanos = row.counters_available != 0 ? ProcessCPU.nanoseconds(ticks: row.cpu_ticks, numerator: timebase.numer, denominator: timebase.denom) : nil
            if let nanos {
                if let previous = previousProcesses[key], let time = previousTime { percent = ProcessCPU.usage(currentNanos: nanos, previousNanos: previous, elapsed: now - time) }
                newCounters[key] = nanos
            }
            snapshot.processes.append(ProcessReading(pid: row.pid, uid: row.uid, startSeconds: row.start_seconds, startMicroseconds: row.start_microseconds, name: name, path: path, memoryBytes: row.counters_available != 0 ? Int64(row.memory_bytes) : -1, cpuNanos: nanos, cpuPercent: percent, parentPID: row.parent_pid, toolHint: hint))
        }
        previousTime = now; previousProcesses = newCounters; toolHints = newHints
        return snapshot
    }
}
