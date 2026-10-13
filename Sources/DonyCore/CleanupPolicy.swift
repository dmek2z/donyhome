import Foundation

public struct CleanupDecision: Sendable {
    public let isRecommended: Bool
    public let reason: String
    public init(_ selected: Bool, _ reason: String) { isRecommended = selected; self.reason = reason }
}

/// A deliberately small, reviewable policy, not a general claim that caches are disposable.
public struct CleanupPolicy: Sendable {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    public static let cacheOwners: Set<String> = [
        "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.VSCode",
        "com.tinyspeck.slackmacgap", "com.spotify.client", "com.figma.Desktop",
        "com.microsoft.edgemac", "com.brave.Browser"
    ]
    public func runningOwner(of url: URL, runningBundleIDs: Set<String>) -> String? {
        for relative in ["Library/Caches", "Library/Logs"] {
            guard let root = try? FileSafety.canonicalRoot(home.appendingPathComponent(relative)), FileSafety.isWithin(url, root: root) else { continue }
            let normalized = url.standardizedFileURL.path
            let base = root.standardizedFileURL.path
            let top = String(normalized.dropFirst(base.count + 1)).split(separator: "/").first.map(String.init) ?? ""
            if let owner = runningBundleIDs.sorted().first(where: { top == $0 || top.hasPrefix($0 + ".") || $0.hasPrefix(top + ".") }) { return owner }
        }
        return nil
    }
    public func reason(for candidate: FileCandidate, now: Date = Date(), runningBundleIDs: Set<String>, token: ScanToken = ScanToken()) throws -> CleanupDecision {
        try token.check()
        guard candidate.kind == .cache || candidate.kind == .log else { return CleanupDecision(false, "직접 선택 필요") }
        let expected = home.appendingPathComponent(candidate.kind == .cache ? "Library/Caches" : "Library/Logs")
        guard let root = try? FileSafety.canonicalRoot(expected), root.path == candidate.root.path else { return CleanupDecision(false, "추천 범위 밖") }
        if runningOwner(of: candidate.url, runningBundleIDs: runningBundleIDs) != nil {
            return CleanupDecision(false, "관련 앱 실행 중")
        }
        let owner = String(candidate.url.path.dropFirst(root.path.count + 1)).split(separator: "/").first.map(String.init) ?? ""
        if candidate.kind == .cache && !Self.cacheOwners.contains(owner) { return CleanupDecision(false, "확인되지 않은 캐시 · 직접 선택") }
        try FileSafety.validate(candidate, token: token)
        let days: Double = candidate.kind == .cache ? 14 : 30
        let cutoff = now.addingTimeInterval(-days * 86400).timeIntervalSince1970
        func acceptable(_ url: URL) throws -> Bool {
            let fp = try FileSafety.fingerprint(url)
            guard fp.isDirectory || fp.isRegular, Double(fp.seconds) + Double(fp.nanoseconds) / 1e9 <= cutoff else { return false }
            if candidate.kind == .log && fp.isRegular {
                let name = url.lastPathComponent.lowercased()
                guard name.hasSuffix(".log") || name.hasSuffix(".log.gz") || name.range(of: #"\.log\.\d+$"#, options: .regularExpression) != nil else { return false }
            }
            return true
        }
        guard try acceptable(candidate.url) else { return CleanupDecision(false, "최근 변경 또는 확인되지 않은 파일") }
        if candidate.fingerprint.isDirectory {
            var failure: Error?
            guard let iterator = FileManager.default.enumerator(at: candidate.url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in failure = error; return false }) else { throw DonyError.unsupported }
            var count = 0
            for case let child as URL in iterator {
                try token.check(); count += 1
                guard count <= 100_000 else { throw DonyError.scanLimit }
                guard try acceptable(child) else { return CleanupDecision(false, "최근 변경 파일 또는 링크 포함") }
            }
            if let failure { throw failure }
        }
        // Detect changes while evaluating the age of descendants.
        try FileSafety.validate(candidate, token: token)
        return CleanupDecision(true, candidate.kind == .cache ? "14일 이상 변경 없는 확인된 앱 캐시" : "30일 이상 지난 로그")
    }
}
