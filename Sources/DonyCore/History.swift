import Foundation

public enum OperationFeedback {
    public static func compose(summary: String, historyError: String?) -> String {
        guard let historyError, !historyError.isEmpty else { return summary }
        return summary + "\n" + historyError
    }
}

public struct ActionRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let kind: String
    public let sourcePath: String
    public let trashPath: String?
    public let bytes: Int64
    public let success: Bool
    public let message: String
    /// 오래된 상세 기록을 한 줄로 요약한 경우의 항목 수. 일반 기록은 nil이다.
    public let count: Int?
    public init(kind: String, sourcePath: String, trashPath: String?, bytes: Int64, success: Bool, message: String) {
        id = UUID(); timestamp = Date(); self.kind = kind; self.sourcePath = sourcePath; self.trashPath = trashPath
        self.bytes = bytes; self.success = success; self.message = message; count = nil
    }
    /// 같은 정리에서 나온 오래된 기록 여러 건을 합친 요약 기록. 용량 합계는 보존한다.
    public init(summaryOf kind: String, success: Bool, timestamp: Date, count: Int, bytes: Int64) {
        id = UUID(); self.timestamp = timestamp; self.kind = kind; sourcePath = "요약 · \(count)개 항목"; trashPath = nil
        self.bytes = bytes; self.success = success; self.count = count
        message = "오래된 상세 기록을 정리 단위로 요약했어요."
    }
}

public struct HistoryStore: Sendable {
    public let directory: URL
    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DonyClean")) { self.directory = directory }
    public func load() throws -> [ActionRecord] {
        let url = directory.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ActionRecord].self, from: Data(contentsOf: url))
    }
    /// 기록이 많아지면 오래된 상세 기록을 정리 단위로 요약한다. 최근 `detailLimit`건은 파일 단위로 그대로 두고,
    /// 같은 종류·성공 여부이고 90초 안에 이어진 오래된 기록은 한 줄로 합친다(용량·개수 합계 보존).
    /// 정리 한 번에 파일이 수천 개 기록돼도 이전 정리 기록이 밀려나 사라지지 않는다. 입력은 최신순.
    public static func compact(_ records: [ActionRecord], detailLimit: Int = 5000, totalLimit: Int = 7000) -> [ActionRecord] {
        guard records.count > detailLimit else { return records }
        var summaries: [ActionRecord] = []
        var run: [ActionRecord] = []
        func flush() {
            guard let first = run.first else { return }
            summaries.append(ActionRecord(summaryOf: first.kind, success: first.success, timestamp: first.timestamp,
                                          count: run.reduce(0) { $0 + ($1.count ?? 1) }, bytes: run.reduce(0) { $0 + $1.bytes }))
            run.removeAll()
        }
        for record in records.dropFirst(detailLimit) {
            if let last = run.last, last.kind != record.kind || last.success != record.success || abs(last.timestamp.timeIntervalSince(record.timestamp)) > 90 { flush() }
            run.append(record)
        }
        flush()
        return Array((Array(records.prefix(detailLimit)) + summaries).prefix(totalLimit))
    }
    public func save(_ records: [ActionRecord]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("history.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(HistoryStore.compact(records)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum TrashService {
    public static func move(_ candidate: FileCandidate, keeping original: FileCandidate? = nil, token: ScanToken = ScanToken(), beforeMutation: (() -> Void)? = nil) -> ActionRecord {
        do {
            try token.check()
            if candidate.kind == .duplicate {
                guard let original else { throw DonyError.missingOriginal }
                try DuplicateFinder.validateCopy(candidate, keeping: original, token: token)
            }
            if candidate.kind == .similar {
                guard let original, original.id != candidate.id, original.fingerprint.identity != candidate.fingerprint.identity else { throw DonyError.missingOriginal }
                try FileSafety.validate(original, token: token)
            }
            try FileSafety.validate(candidate, token: token)
            if candidate.kind == .application {
                guard candidate.url.pathExtension == "app", let id = Bundle(url: candidate.url)?.bundleIdentifier,
                      !id.hasPrefix("com.apple."), id != "local.dony.DonyClean" else { throw DonyError.unsafePath }
            }
            var destination: NSURL?
            beforeMutation?()
            try FileManager.default.trashItem(at: candidate.url, resultingItemURL: &destination)
            return ActionRecord(kind: "휴지통 이동", sourcePath: candidate.url.path, trashPath: destination?.path, bytes: candidate.bytes, success: true, message: "휴지통으로 이동했습니다.")
        } catch {
            return ActionRecord(kind: "휴지통 이동", sourcePath: candidate.url.path, trashPath: nil, bytes: 0, success: false, message: error.localizedDescription)
        }
    }
}
