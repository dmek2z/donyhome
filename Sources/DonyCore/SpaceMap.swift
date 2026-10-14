import Foundation

public struct SpaceEntry: Identifiable, Sendable {
    public var id: String { candidate.id }
    public let candidate: FileCandidate
    public let bytes: Int64
    public var selectable = true
}
public struct SpaceResult: Sendable {
    public var entries: [SpaceEntry] = []
    public var issues: [ScanIssue] = []
    public var cancelled = false
    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    public init() {}
}
public enum SpaceMap {
    public static func placeholder(_ url: URL) throws -> Bool {
        let cloud = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        return cloud.isUbiquitousItem == true && cloud.ubiquitousItemDownloadingStatus != .current
    }
    public static func validateSelection(_ item: FileCandidate, isPlaceholder: (URL) throws -> Bool = placeholder) throws {
        try FileSafety.validate(item)
        guard try !isPlaceholder(item.url) else { throw DonyError.unsupported }
        if item.fingerprint.isDirectory {
            var failure: Error?
            guard let iterator = FileManager.default.enumerator(at: item.url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in failure = error; return false }) else { throw DonyError.unsupported }
            var count = 0
            for case let url as URL in iterator {
                count += 1; guard count <= 100_000 else { throw DonyError.scanLimit }
                let fp = try FileSafety.fingerprint(url)
                if !fp.isDirectory && !fp.isRegular { iterator.skipDescendants(); continue }
                guard try !isPlaceholder(url) else { throw DonyError.unsupported }
            }
            if let failure { throw failure }
        }
        try FileSafety.validate(item)
    }
    public static func scan(root: URL, token: ScanToken, progress: Scanner.Progress? = nil, isPlaceholder: @Sendable (URL) throws -> Bool = placeholder) -> SpaceResult {
        var result = SpaceResult()
        guard !token.isCancelled else { result.cancelled = true; return result }
        do {
            let base = try FileSafety.canonicalRoot(root)
            guard FileSafety.allowedRoot(base, kind: .space), try FileSafety.fingerprint(base).isDirectory else { throw DonyError.unsafePath }
            var identities = Set<String>(); var visited = 0
            for top in try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                try token.check()
                do {
                    let fingerprint = try FileSafety.fingerprint(top)
                    guard fingerprint.isRegular || fingerprint.isDirectory else { continue }
                    var bytes: Int64 = 0; var excludedCloud = false
                    func consume(_ url: URL) throws -> Bool {
                        try token.check(); visited += 1
                        guard visited <= 100_000 else { throw DonyError.scanLimit }
                        let fp = try FileSafety.fingerprint(url)
                        guard fp.isDirectory || fp.isRegular else { return false }
                        if try isPlaceholder(url) { excludedCloud = true; result.issues.append(ScanIssue(path: url.path, message: "내려받지 않은 클라우드 항목")); return false }
                        if fp.isRegular && identities.insert(fp.identity).inserted { bytes += max(0, fp.size) }
                        if visited % 100 == 0 { progress?(visited, url.lastPathComponent) }
                        return fp.isDirectory
                    }
                    let descend = try consume(top)
                    if excludedCloud { continue }
                    if descend {
                        var failure: Error?
                        guard let iterator = FileManager.default.enumerator(at: top, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in failure = error; return false }) else { throw DonyError.unsupported }
                        for case let child as URL in iterator { if try !consume(child) { iterator.skipDescendants() } }
                        if let failure { throw failure }
                    }
                    let item = try FileCandidate.capture(url: top, root: base, kind: .space, token: token)
                    result.entries.append(SpaceEntry(candidate: item, bytes: bytes, selectable: !excludedCloud))
                } catch {
                    if token.isCancelled { throw error }
                    result.issues.append(ScanIssue(path: top.path, error: error))
                    if (error as? DonyError) == .scanLimit { throw error }
                }
            }
        } catch { if token.isCancelled { result.cancelled = true } else { result.issues.append(ScanIssue(path: root.path, error: error)) } }
        result.entries.sort { $0.bytes > $1.bytes }
        return result
    }
}
