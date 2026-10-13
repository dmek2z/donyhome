import Foundation

public struct SmartScanResult: Sendable {
    public var cleanup = ScanResult()
    public var decisions: [String: CleanupDecision] = [:]
    public var largeFiles = ScanResult()
    public var duplicates = DuplicateResult()
    public var developer = DeveloperResult()
    public var leftovers = LeftoverResult()
    public var clutter = ClutterResult()
    public var trash = ScanResult()
    public var similar = SimilarResult()
    public var space = SpaceResult()
    public var applications = ApplicationResult()
    public var cancelled = false
    public var recommended: [FileCandidate] { cleanup.items.filter { decisions[$0.id]?.isRecommended == true } }
    public var issues: [ScanIssue] { cleanup.issues + developer.issues + largeFiles.issues + duplicates.issues + applications.issues + leftovers.issues + clutter.oldFiles.issues + space.issues + similar.issues + trash.issues }
    public init() {}
}

public enum SmartScanner {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, folder: URL, runningBundleIDs: Set<String>, runningTools: Set<String> = RunningTools.read(), token: ScanToken, includeApplications: Bool = true, progress: Scanner.Progress? = nil) -> SmartScanResult {
        var result = SmartScanResult()
        let roots: [(URL, CandidateKind)] = [(home.appendingPathComponent("Library/Caches"), .cache), (home.appendingPathComponent("Library/Logs"), .log)]
        progress?(0, "캐시 · 로그")
        result.cleanup = Scanner.cleanup(roots: roots, excluding: runningBundleIDs, token: token, progress: progress)
        let policy = CleanupPolicy(home: home)
        for item in result.cleanup.items {
            if token.isCancelled { break }
            do { result.decisions[item.id] = try policy.reason(for: item, runningBundleIDs: runningBundleIDs, token: token) }
            catch {
                if !token.isCancelled { result.cleanup.issues.append(ScanIssue(path: item.id, error: error)) }
            }
        }
        if !token.isCancelled {
            progress?(0, "개발 캐시")
            result.developer = DeveloperCleanup.scan(home: home, runningTools: runningTools.union(runningBundleIDs), token: token)
        }
        if !token.isCancelled {
            progress?(0, "오래된 파일 · 설치 파일")
            result.clutter = ClutterScanner.scan(root: folder, token: token, progress: progress)
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
        if !token.isCancelled {
            progress?(0, "앱 잔여물 후보")
            result.leftovers = LeftoverScanner.scan(home: home, installedIDs: Set(result.applications.apps.map(\.bundleID)), runningIDs: runningBundleIDs, token: token)
        }
        if !token.isCancelled {
            progress?(0, "폴더 용량 지도")
            result.space = SpaceMap.scan(root: folder, token: token, progress: progress)
        }
        if !token.isCancelled {
            progress?(0, "유사 사진")
            result.similar = SimilarPhotoFinder.find(root: folder, token: token, progress: progress)
        }
        if !token.isCancelled {
            progress?(0, "휴지통 항목")
            result.trash = TrashEmptyService.scan(home: home, token: token)
        }
        result.cancelled = result.trash.cancelled || result.similar.cancelled || result.developer.cancelled || result.leftovers.cancelled || result.clutter.oldFiles.cancelled || result.clutter.installers.cancelled || result.space.cancelled || token.isCancelled || result.cleanup.cancelled || result.largeFiles.cancelled || result.duplicates.cancelled || result.applications.cancelled
        // Partial results are useful for review, but never become an executable recommendation plan.
        if result.cancelled { result.decisions.removeAll() }
        return result
    }
}
