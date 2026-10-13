import Foundation
import IOKit.ps
import DonySystemBridge

public struct NetworkCounters: Sendable {
    public let received, sent, generation: UInt64
    public init(received: UInt64, sent: UInt64, generation: UInt64) { self.received = received; self.sent = sent; self.generation = generation }
    public func rates(since previous: Self, elapsed: Double) -> (received: Double, sent: Double)? {
        guard generation == previous.generation, elapsed > 0, received >= previous.received, sent >= previous.sent else { return nil }
        return (Double(received - previous.received) / elapsed, Double(sent - previous.sent) / elapsed)
    }
}
public struct BatteryReading: Codable, Sendable {
    public let percent: Double
    public let charging, externalPower: Bool
    public static func parse(_ description: [String: Any]) -> BatteryReading? {
        guard let current = description[kIOPSCurrentCapacityKey] as? NSNumber, let maximum = description[kIOPSMaxCapacityKey] as? NSNumber, maximum.doubleValue > 0 else { return nil }
        return BatteryReading(percent: min(100, max(0, current.doubleValue / maximum.doubleValue * 100)), charging: (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false, externalPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
    }
    static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType, let reading = parse(description) { return reading }
        }
        return nil
    }
}

public enum RunningTools {
    public static func read() -> Set<String> {
        var rows = Array(repeating: DCProcess(), count: 4096)
        let count = rows.withUnsafeMutableBufferPointer { dc_read_processes($0.baseAddress, Int32($0.count)) }
        return Set((0..<max(0, Int(count))).flatMap { index -> [String] in
            var row = rows[index]
            let name = withUnsafePointer(to: &row.name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
            let path = withUnsafePointer(to: &row.path) { $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) } }
            return [name.lowercased(), URL(fileURLWithPath: path).lastPathComponent.lowercased()]
        })
    }
}
