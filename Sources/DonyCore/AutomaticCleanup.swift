import Foundation

/// Automatic cleanup is limited to old regular files, never whole folders or personal files.
public enum AutomaticCleanup {
    public static func isDue(enabled: Bool, lastAttempt: Date?, now: Date = Date()) -> Bool {
        enabled && (lastAttempt.map { now.timeIntervalSince($0) >= 86400 } ?? true)
    }

    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, now: Date = Date(), runningOwners: Set<String>, token: ScanToken, progress: Scanner.Progress? = nil) -> ScanResult {
        var result = ScanResult()
        let policy = CleanupPolicy(home: home)
        for (relative, kind) in [("Library/Caches", CandidateKind.cache), ("Library/Logs", .log)] {
            if token.isCancelled { break }
            let root = home.appendingPathComponent(relative)
            do {
                let base = try FileSafety.canonicalRoot(root)
                guard FileSafety.allowedRoot(base, kind: kind), try FileSafety.fingerprint(base).isDirectory else { throw DonyError.unsafePath }
                guard let iterator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [], errorHandler: { url, error in
                    if result.issues.count < 100 { result.issues.append(ScanIssue(path: url.path, error: error)) }
                    return true
                }) else { throw DonyError.unsupported }
                for case let url as URL in iterator {
                    try token.check()
                    result.visited += 1
                    guard result.visited <= 100_000 else { throw DonyError.scanLimit }
                    progress?(result.visited, url.lastPathComponent)
                    let owner = String(url.path.dropFirst(base.path.count + 1)).split(separator: "/").first.map(String.init) ?? ""
                    if (kind == .cache && !CleanupPolicy.cacheOwners.contains(owner)) || policy.runningOwner(of: url, runningBundleIDs: runningOwners) != nil {
                        iterator.skipDescendants(); continue
                    }
                    do {
                        let fp = try FileSafety.fingerprint(url)
                        if fp.isDirectory { continue }
                        iterator.skipDescendants()
                        guard fp.isRegular, fp.size > 0, Double(fp.seconds) + Double(fp.nanoseconds) / 1e9 <= now.addingTimeInterval(-(kind == .cache ? 14 : 30) * 86400).timeIntervalSince1970 else { continue }
                        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current { continue }
                        let candidate = try FileCandidate.capture(url: url, root: base, kind: kind, token: token)
                        if try policy.reason(for: candidate, now: now, runningBundleIDs: runningOwners, token: token).isRecommended { result.items.append(candidate) }
                    } catch {
                        if token.isCancelled { throw DonyError.cancelled }
                        if result.issues.count < 100 { result.issues.append(ScanIssue(path: url.path, error: error)) }
                    }
                }
            } catch {
                if !token.isCancelled { result.issues.append(ScanIssue(path: root.path, error: error)) }
                if case DonyError.scanLimit = error { result.cancelled = true; break }
            }
        }
        result.cancelled = result.cancelled || token.isCancelled
        if result.cancelled { result.items.removeAll() }
        result.items.sort { $0.id < $1.id }
        return result
    }
}
