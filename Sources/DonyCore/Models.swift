import Foundation

public enum CandidateKind: String, Codable, Sendable { case cache, log, large, duplicate, application, support }

public struct FileFingerprint: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let mode: UInt32
    public let size: Int64
    public let seconds: Int64
    public let nanoseconds: Int64
    public var isDirectory: Bool { mode & 0o170000 == 0o040000 }
    public var isRegular: Bool { mode & 0o170000 == 0o100000 }
    public var identity: String { "\(device):\(inode)" }
    public func sameObject(as other: Self) -> Bool { device == other.device && inode == other.inode && mode == other.mode }
}

public struct PathAnchor: Codable, Sendable {
    public let url: URL
    public let fingerprint: FileFingerprint
}

public struct FileCandidate: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let root: URL
    public let kind: CandidateKind
    public let fingerprint: FileFingerprint
    public let anchors: [PathAnchor]
    public let bytes: Int64
    public let treeStamp: String?
    public var name: String { url.lastPathComponent }
}

public struct ScanIssue: Identifiable, Codable, Sendable {
    public var id: String { path + message }
    public let path: String
    public let message: String
    public init(path: String, message: String) { self.path = path; self.message = message }
}

public struct ScanResult: Sendable {
    public var items: [FileCandidate] = []
    public var issues: [ScanIssue] = []
    public var cancelled = false
    public var visited = 0
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public init() {}
}

public final class ScanToken: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    public func check() throws { if isCancelled { throw DonyError.cancelled } }
}

public enum DonyError: LocalizedError {
    case unsafePath, changed, unsupported, cancelled, scanLimit, missingOriginal, processChanged, protectedProcess
    public var errorDescription: String? {
        switch self {
        case .unsafePath: return "허용 범위를 벗어나거나 링크가 포함된 경로입니다."
        case .changed: return "검사 이후 항목이 변경되었습니다. 다시 검사해 주세요."
        case .unsupported: return "이 항목은 안전하게 확인할 수 없습니다."
        case .cancelled: return "검사가 중단되었습니다."
        case .scanLimit: return "항목이 너무 많습니다. 더 작은 폴더를 선택해 주세요."
        case .missingOriginal: return "보관할 원본이 변경되었거나 사라졌습니다. 다시 검사해 주세요."
        case .processChanged: return "앱이 종료되었거나 프로세스가 변경되었습니다."
        case .protectedProcess: return "시스템 또는 보호된 프로세스는 종료할 수 없습니다."
        }
    }
}

public enum DisplayFormat {
    public static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
    public static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
}
