import Foundation

public struct CleanupDecision: Sendable {
    public let isRecommended: Bool
    public let reason: String
    public init(_ selected: Bool, _ reason: String) { isRecommended = selected; self.reason = reason }
}

/// A deliberately small, reviewable policy, not a general claim that caches are disposable.
public struct CleanupPolicy: Sendable {
    public let home: URL
    public let days: Int?
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, days: Int? = nil) { self.home = (try? FileSafety.canonicalRoot(home)) ?? home; self.days = days }
    public static let cacheOwners: Set<String> = [
        "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.VSCode",
        "com.tinyspeck.slackmacgap", "com.spotify.client", "com.figma.Desktop",
        "com.microsoft.edgemac", "com.brave.Browser"
    ]
    public func runningOwner(of url: URL, runningBundleIDs: Set<String>) -> String? {
        for relative in ["Library/Caches", "Library/Logs", "Library/Application Support"] {
            guard let root = try? FileSafety.canonicalRoot(home.appendingPathComponent(relative)), FileSafety.isWithin(url, root: root) else { continue }
            let normalized = url.standardizedFileURL.path
            let base = root.standardizedFileURL.path
            let top = String(normalized.dropFirst(base.count + 1)).split(separator: "/").first.map(String.init) ?? ""
            let aliases = (CacheScopes.namedOwners[top] ?? []).union([top])
            if let owner = runningBundleIDs.sorted().first(where: { running in aliases.contains { alias in
                running.lowercased() == alias.lowercased() || running.lowercased().hasPrefix(alias.lowercased() + ".") || alias.lowercased().hasPrefix(running.lowercased() + ".")
            } }) { return owner }
        }
        return nil
    }
    public func reason(for candidate: FileCandidate, now: Date = Date(), runningBundleIDs: Set<String>, token: ScanToken = ScanToken()) throws -> CleanupDecision {
        try token.check()
        guard candidate.kind == .cache || candidate.kind == .log else { return CleanupDecision(false, "직접 선택 필요") }
        guard CacheScopes.allowedScope(root: candidate.root, home: home, kind: candidate.kind) else { return CleanupDecision(false, "추천 범위 밖") }
        if runningOwner(of: candidate.url, runningBundleIDs: runningBundleIDs) != nil {
            return CleanupDecision(false, "관련 앱 실행 중")
        }
        let owner = CacheScopes.owner(of: candidate.url, home: home) ?? ""
        if candidate.kind == .cache && !Self.cacheOwners.contains(owner) && !CacheScopes.isKnown(root: candidate.url, home: home) { return CleanupDecision(false, "확인되지 않은 캐시 · 직접 선택") }
        try FileSafety.validate(candidate, token: token)
        var parent = candidate.fingerprint.isDirectory ? candidate.url : candidate.url.deletingLastPathComponent()
        while parent.path == candidate.root.path || FileSafety.isWithin(parent, root: candidate.root) {
            if CacheScopes.containsProject(parent) { return CleanupDecision(false, "프로젝트 원본 · 보관") }
            if parent.path == candidate.root.path { break }
            parent.deleteLastPathComponent()
        }
        let retention = days ?? (candidate.kind == .cache ? 14 : 30)
        guard (1...3650).contains(retention), !CacheScopes.isProtected(candidate.url) else { return CleanupDecision(false, "보호된 경로 또는 잘못된 보관 기간") }
        let days = Double(retention)
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
        return CleanupDecision(true, "\(retention)일 이상 변경 없는 " + (candidate.kind == .cache ? "확인된 캐시" : "로그"))
    }
}
