import Foundation

public enum StorageHealth: String, Codable, Sendable { case unknown, normal, low, critical }
public struct StorageAssessment: Sendable {
    public let health: StorageHealth
    public let available: Int64?
    public let total: Int64?
    public var needsAttention: Bool { health == .low || health == .critical }
    public var title: String { switch health { case .unknown: return "저장 공간 확인 필요"; case .normal: return "저장 공간 여유"; case .low: return "저장 공간이 부족해지고 있어요"; case .critical: return "저장 공간이 거의 없어요" } }
    public static func resolve(available: Int64?, total: Int64?, warningGB: Int = 20, recovering: Bool = false) -> Self {
        guard let available, let total, total > 0, available >= 0, available <= total else { return Self(health: .unknown, available: nil, total: nil) }
        let gb: Int64 = 1_000_000_000
        let warning = min(Int64(max(1, min(1000, warningGB))) * gb, total / 5)
        let critical = min(5 * gb, total / 50)
        let threshold = recovering ? warning + min(2 * gb, total / 100) : warning
        return Self(health: available <= critical ? .critical : available <= threshold ? .low : .normal, available: available, total: total)
    }
}
public struct CleanupOutcome: Sendable {
    public let movedBytes: Int64
    public let successful: Int
    public let failed: Int
    public let beforeAvailable: Int64?
    public let afterAvailable: Int64?
    public let permanent: Bool
    public var observedDelta: Int64? {
        guard let beforeAvailable, let afterAvailable, beforeAvailable >= 0, afterAvailable >= 0 else { return nil }
        return afterAvailable - beforeAvailable
    }
    public var observedGain: Int64? { observedDelta.map { max(0, $0) } }
    public init(movedBytes: Int64, successful: Int, failed: Int, beforeAvailable: Int64?, afterAvailable: Int64?, permanent: Bool = false) {
        self.movedBytes = movedBytes; self.successful = successful; self.failed = failed
        self.beforeAvailable = beforeAvailable; self.afterAvailable = afterAvailable; self.permanent = permanent
    }
}
public struct StorageNoticeGate: Sendable {
    public var lowSince: Date?
    public var lastNotice: Date?
    public init(lastNotice: Date? = nil) { self.lastNotice = lastNotice }
    public mutating func update(_ assessment: StorageAssessment, now: Date, enabled: Bool, delay: TimeInterval = 30, cooldown: TimeInterval = 3600) -> Bool {
        guard assessment.needsAttention else { lowSince = nil; return false }
        if lowSince == nil { lowSince = now }
        guard enabled, now.timeIntervalSince(lowSince!) >= delay, lastNotice.map({ now.timeIntervalSince($0) >= cooldown }) ?? true else { return false }
        lastNotice = now; return true
    }
}

/// Captures free space once, immediately before the first actual filesystem mutation.
public final class CleanupSpaceMeasurement: @unchecked Sendable {
    private let lock = NSLock()
    private var captured = false
    private var value: Int64?
    public init() {}
    public var beforeAvailable: Int64? { lock.lock(); defer { lock.unlock() }; return value }
    public func captureBeforeMutation(read: () -> Int64? = {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: FileManager.default.homeDirectoryForCurrentUser.path)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
    }) {
        lock.lock(); defer { lock.unlock() }
        guard !captured else { return }
        captured = true; value = read()
    }
}
