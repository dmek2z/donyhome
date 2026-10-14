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
    public init(kind: String, sourcePath: String, trashPath: String?, bytes: Int64, success: Bool, message: String) {
        id = UUID(); timestamp = Date(); self.kind = kind; self.sourcePath = sourcePath; self.trashPath = trashPath
        self.bytes = bytes; self.success = success; self.message = message
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
    public func save(_ records: [ActionRecord]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("history.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Array(records.prefix(500))).write(to: url, options: .atomic)
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
