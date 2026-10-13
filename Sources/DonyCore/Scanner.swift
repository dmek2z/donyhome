import Foundation

public enum Scanner {
    public typealias Progress = @Sendable (Int, String) -> Void

    public static func largeFiles(root: URL, minimumBytes: Int64 = 100_000_000, token: ScanToken, progress: Progress? = nil) -> ScanResult {
        walk(root: root, minimumBytes: minimumBytes, kind: .large, token: token, progress: progress)
    }

    static func walk(root: URL, minimumBytes: Int64, kind: CandidateKind, token: ScanToken, progress: Progress?) -> ScanResult {
        var result = ScanResult()
        if token.isCancelled { result.cancelled = true; return result }
        let base = (try? FileSafety.canonicalRoot(root)) ?? root.standardizedFileURL
        do {
            guard FileSafety.allowedRoot(base, kind: kind), try FileSafety.fingerprint(base).isDirectory else { throw DonyError.unsafePath }
            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
            guard let iterator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
                if result.issues.count < 100 { result.issues.append(ScanIssue(path: url.path, message: error.localizedDescription)) }
                return true
            }) else { throw DonyError.unsupported }
            for case let url as URL in iterator {
                if token.isCancelled { result.cancelled = true; break }
                result.visited += 1
                if result.visited % 100 == 0 { progress?(result.visited, url.lastPathComponent) }
                guard result.visited <= 100_000 else { throw DonyError.scanLimit }
                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    if values.isSymbolicLink == true || values.isPackage == true { iterator.skipDescendants(); continue }
                    if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current { continue }
                    guard values.isRegularFile == true, Int64(values.fileSize ?? 0) >= minimumBytes else { continue }
                    result.items.append(try FileCandidate.capture(url: url, root: base, kind: kind, token: token))
                } catch {
                    if result.issues.count < 100 { result.issues.append(ScanIssue(path: url.path, message: error.localizedDescription)) }
                }
            }
        } catch { result.issues.append(ScanIssue(path: base.path, message: error.localizedDescription)) }
        result.items.sort { $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes > $1.bytes }
        progress?(result.visited, "완료")
        return result
    }

    public static func cleanup(roots: [(URL, CandidateKind)], excluding: Set<String> = [], token: ScanToken, progress: Progress? = nil) -> ScanResult {
        var result = ScanResult()
        for (root, kind) in roots {
            if token.isCancelled { result.cancelled = true; break }
            do {
                let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                for url in children.sorted(by: { $0.path < $1.path }) {
                    if token.isCancelled { result.cancelled = true; break }
                    result.visited += 1; progress?(result.visited, url.lastPathComponent)
                    if excluding.contains(url.lastPathComponent) {
                        result.issues.append(ScanIssue(path: url.path, message: "사용 중인 앱의 항목이라 건너뛰었습니다.")); continue
                    }
                    do {
                        let candidate = try FileCandidate.capture(url: url, root: root, kind: kind, token: token)
                        if candidate.bytes > 0 { result.items.append(candidate) }
                    } catch {
                        if token.isCancelled { result.cancelled = true; break }
                        if result.issues.count < 100 { result.issues.append(ScanIssue(path: url.path, message: error.localizedDescription)) }
                    }
                }
            } catch { result.issues.append(ScanIssue(path: root.path, message: error.localizedDescription)) }
        }
        result.items.sort { $0.bytes > $1.bytes }
        return result
    }
}
