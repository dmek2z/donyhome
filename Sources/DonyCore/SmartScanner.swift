import Foundation

public struct SmartScanResult: Sendable {
    public var cleanup = ScanResult()
    public var decisions: [String: CleanupDecision] = [:]
    public var largeFiles = ScanResult()
    public var duplicates = DuplicateResult()
    public var applications = ApplicationResult()
    public var cancelled = false
    public var recommended: [FileCandidate] { cleanup.items.filter { decisions[$0.id]?.isRecommended == true } }
    public var issues: [ScanIssue] { cleanup.issues + largeFiles.issues + duplicates.issues + applications.issues }
    public init() {}
}

public enum SmartScanner {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, folder: URL, runningBundleIDs: Set<String>, token: ScanToken, includeApplications: Bool = true, progress: Scanner.Progress? = nil) -> SmartScanResult {
        var result = SmartScanResult()
        let roots: [(URL, CandidateKind)] = [(home.appendingPathComponent("Library/Caches"), .cache), (home.appendingPathComponent("Library/Logs"), .log)]
        progress?(0, "캐시 · 로그")
        result.cleanup = Scanner.cleanup(roots: roots, excluding: runningBundleIDs, token: token, progress: progress)
        let policy = CleanupPolicy(home: home)
        for item in result.cleanup.items {
            if token.isCancelled { break }
            do { result.decisions[item.id] = try policy.reason(for: item, runningBundleIDs: runningBundleIDs, token: token) }
            catch {
                if !token.isCancelled { result.cleanup.issues.append(ScanIssue(path: item.id, message: error.localizedDescription)) }
            }
        }
        if !token.isCancelled {
            progress?(0, "큰 파일 · " + folder.lastPathComponent)
            result.largeFiles = Scanner.largeFiles(root: folder, token: token, progress: progress)
        }
        if !token.isCancelled {
            progress?(0, "중복 파일 · " + folder.lastPathComponent)
            result.duplicates = DuplicateFinder.find(root: folder, token: token, progress: progress)
            result.duplicates.groups = result.duplicates.groups.compactMap { group in
                if policy.runningOwner(of: group.original.url, runningBundleIDs: runningBundleIDs) != nil {
                    result.duplicates.issues.append(ScanIssue(path: group.original.id, message: "실행 중인 앱의 캐시·로그라 중복 추천에서 제외했습니다.")); return nil
                }
                let copies = group.copies.filter { item in
                    guard policy.runningOwner(of: item.url, runningBundleIDs: runningBundleIDs) == nil else {
                        result.duplicates.issues.append(ScanIssue(path: item.id, message: "실행 중인 앱의 캐시·로그라 중복 추천에서 제외했습니다.")); return false
                    }
                    return true
                }
                return copies.isEmpty ? nil : DuplicateGroup(original: group.original, copies: copies)
            }
        }
        if !token.isCancelled && includeApplications {
            progress?(0, "설치 앱")
            result.applications = ApplicationScanner.inventory(token: token)
        }
        result.cancelled = token.isCancelled || result.cleanup.cancelled || result.largeFiles.cancelled || result.duplicates.cancelled || result.applications.cancelled
        // Partial results are useful for review, but never become an executable recommendation plan.
        if result.cancelled { result.decisions.removeAll() }
        return result
    }
}
