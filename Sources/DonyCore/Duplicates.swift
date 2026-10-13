import Foundation
import CryptoKit

public struct DuplicateGroup: Identifiable, Sendable {
    public var id: String { original.id }
    public let original: FileCandidate
    public let copies: [FileCandidate]
    public var bytesRecoverable: Int64 { copies.reduce(0) { $0 + $1.bytes } }
    public init(original: FileCandidate, copies: [FileCandidate]) { self.original = original; self.copies = copies }
}

public struct DuplicateResult: Sendable {
    public var groups: [DuplicateGroup] = []
    public var issues: [ScanIssue] = []
    public var cancelled = false
    public var visited = 0
    public init() {}
}

public enum DuplicateFinder {
    public static func find(root: URL, token: ScanToken, progress: Scanner.Progress? = nil) -> DuplicateResult {
        let scan = Scanner.walk(root: root, minimumBytes: 1, kind: .duplicate, token: token, progress: progress)
        var result = DuplicateResult()
        result.issues = scan.issues; result.cancelled = scan.cancelled; result.visited = scan.visited
        guard !scan.cancelled else { return result }
        var seen = Set<String>()
        let unique = scan.items.filter { seen.insert($0.fingerprint.identity).inserted }
        for (_, candidates) in Dictionary(grouping: unique, by: \.bytes).sorted(by: { $0.key > $1.key }) where candidates.count > 1 {
            var hashes: [String: [FileCandidate]] = [:]
            for candidate in candidates.sorted(by: { $0.url.path < $1.url.path }) {
                if token.isCancelled { result.cancelled = true; return result }
                progress?(result.visited, "중복 확인 · " + candidate.name)
                do { hashes[try digest(candidate, token: token), default: []].append(candidate) }
                catch {
                    if token.isCancelled { result.cancelled = true; return result }
                    result.issues.append(ScanIssue(path: candidate.url.path, message: error.localizedDescription))
                }
            }
            for (_, matches) in hashes where matches.count > 1 {
                // Hash identifies potential matches; byte comparison is the actual identity check.
                var remaining = matches
                while remaining.count > 1 {
                    if token.isCancelled { result.cancelled = true; return result }
                    let original = remaining.removeFirst()
                    var copies: [FileCandidate] = []; var different: [FileCandidate] = []
                    for candidate in remaining {
                        if token.isCancelled { result.cancelled = true; return result }
                        progress?(result.visited, "사본 비교 · " + candidate.name)
                        do {
                            if try equalBytes(original.url, candidate.url, token: token) { copies.append(candidate) }
                            else { different.append(candidate) }
                        } catch {
                            if token.isCancelled { result.cancelled = true; return result }
                            result.issues.append(ScanIssue(path: candidate.url.path, message: error.localizedDescription))
                        }
                    }
                    if !copies.isEmpty { result.groups.append(DuplicateGroup(original: original, copies: copies)) }
                    remaining = different
                }
            }
        }
        result.cancelled = token.isCancelled
        result.groups.sort { $0.bytesRecoverable > $1.bytesRecoverable }
        return result
    }

    public static func validateCopy(_ copy: FileCandidate, keeping original: FileCandidate, token: ScanToken) throws {
        do {
            try FileSafety.validate(original, token: token)
            try FileSafety.validate(copy, token: token)
            guard original.fingerprint.identity != copy.fingerprint.identity,
                  try equalBytes(original.url, copy.url, token: token) else { throw DonyError.missingOriginal }
            try FileSafety.validate(original, token: token)
            try FileSafety.validate(copy, token: token)
        } catch { throw DonyError.missingOriginal }
    }

    private static func digest(_ candidate: FileCandidate, token: ScanToken) throws -> String {
        try FileSafety.validate(candidate)
        let handle = try FileHandle(forReadingFrom: candidate.url); defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try token.check()
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        try FileSafety.validate(candidate)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func equalBytes(_ a: URL, _ b: URL, token: ScanToken) throws -> Bool {
        try token.check()
        let first = try FileHandle(forReadingFrom: a); defer { try? first.close() }
        let second = try FileHandle(forReadingFrom: b); defer { try? second.close() }
        while true {
            try token.check()
            let x = try first.read(upToCount: 1_048_576) ?? Data()
            let y = try second.read(upToCount: 1_048_576) ?? Data()
            if x != y { return false }
            if x.isEmpty { return true }
        }
    }
}
