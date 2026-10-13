import Testing
import Foundation
@testable import DonyCore

@Suite struct TelemetryTests {
    @Test func cpuUsesCounterDelta() {
        let a = CPUCounters(user: 100, system: 50, idle: 800, nice: 0)
        let b = CPUCounters(user: 120, system: 60, idle: 870, nice: 0)
        expectEqual(b.usage(since: a), 30)
        expectEqual(a.usage(since: b), nil)
        expectEqual(a.usage(since: a), nil)
    }
    @Test func processCPUCanExceedOneHundredAcrossCores() {
        expectEqual(ProcessCPU.usage(currentNanos: 5_000_000_000, previousNanos: 1_000_000_000, elapsed: 2), 200)
        expectEqual(ProcessCPU.usage(currentNanos: 100, previousNanos: 200, elapsed: 1), nil)
        expectEqual(ProcessCPU.usage(currentNanos: 100, previousNanos: 0, elapsed: 0), nil)
    }
    @Test func convertsAppleSiliconMachTicksBeforeCPUPercentage() {
        expectEqual(ProcessCPU.nanoseconds(ticks: 2_400_000, numerator: 125, denominator: 3), 100_000_000)
        expectEqual(ProcessCPU.nanoseconds(ticks: 100, numerator: 1, denominator: 1), 100)
        expectEqual(ProcessCPU.nanoseconds(ticks: 100, numerator: 125, denominator: 0), nil)
        expectEqual(ProcessCPU.nanoseconds(ticks: UInt64.max, numerator: 125, denominator: 3), nil)
    }
    @Test func rejectsForeignProtectedAndOwnProcess() {
        let app = ProcessReading(pid: 42, uid: 501, startSeconds: 100, startMicroseconds: 1, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari", memoryBytes: 100, cpuNanos: 100, cpuPercent: 10)
        expectTrue(ProcessPolicy.canQuit(app, currentUID: 501, ownPID: 999, regularApplication: true))
        expectFalse(ProcessPolicy.canQuit(app, currentUID: 502, ownPID: 999, regularApplication: true))
        expectFalse(ProcessPolicy.canQuit(app, currentUID: 501, ownPID: 42, regularApplication: true))
        expectFalse(ProcessPolicy.canQuit(app, currentUID: 501, ownPID: 999, regularApplication: false))
        let protected = ProcessReading(pid: 43, uid: 501, startSeconds: 100, startMicroseconds: 1, name: "WindowServer", path: "/System/Library/WindowServer", memoryBytes: 1, cpuNanos: 1, cpuPercent: 1)
        expectFalse(ProcessPolicy.canQuit(protected, currentUID: 501, ownPID: 999, regularApplication: true))
    }
    @Test func reusedPIDIsRejected() {
        let a = ProcessReading(pid: 42, uid: 501, startSeconds: 100, startMicroseconds: 1, name: "app", path: "app", memoryBytes: 1, cpuNanos: 1, cpuPercent: 1)
        let b = ProcessReading(pid: 42, uid: 501, startSeconds: 101, startMicroseconds: 1, name: "app", path: "app", memoryBytes: 1, cpuNanos: 1, cpuPercent: 1)
        expectFalse(ProcessPolicy.sameIdentity(a, b))
        expectTrue(ProcessPolicy.sameIdentity(a, a))
    }
}
