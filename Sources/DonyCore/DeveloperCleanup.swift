import Foundation

public struct DeveloperResult: Sendable {
    public var items: [FileCandidate] = []
    public var decisions: [String: CleanupDecision] = [:]
    public var issues: [ScanIssue] = []
    public var cancelled = false
    public var recommended: [FileCandidate] { items.filter { decisions[$0.id]?.isRecommended == true } }
    public init() {}
}
public enum DeveloperCleanup {
    private static let targets: [(String, Set<String>)] = [
        ("Library/Developer/Xcode/DerivedData", ["xcode", "xcodebuild", "swift", "swift-frontend", "clang", "com.apple.dt.xcode"]),
        (".npm/_cacache", ["npm", "npx", "node"]),
        ("Library/Caches/pip", ["pip", "pip3", "python", "python3"]),
        ("Library/Caches/Homebrew", ["brew", "ruby"]),
        ("Library/Caches/Yarn", ["yarn", "node"]),
        ("Library/Caches/pnpm", ["pnpm", "pnpx", "node"])
    ]
    public static func label(_ item: FileCandidate) -> String {
        if item.id.contains("/Xcode/DerivedData/") { return "Xcode · " + item.url.deletingLastPathComponent().lastPathComponent + " · " + item.name }
        if item.id.contains("/.npm/_cacache") { return "npm 다운로드 캐시" }
        return item.name + " 다운로드 캐시"
    }
    public static func activeOwner(of url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser, runningTools: Set<String>) -> Bool {
        guard let base = try? FileSafety.canonicalRoot(home) else { return true }
        let running = Set(runningTools.map { $0.lowercased() })
        return targets.contains { path, tools in
            let target = base.appendingPathComponent(path)
            return (url.path == target.path || FileSafety.isWithin(url, root: target) || FileSafety.isWithin(target, root: url)) && !running.isDisjoint(with: tools)
        }
    }
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, runningTools: Set<String>, token: ScanToken, now: Date = Date(), days: Int = 7) -> DeveloperResult {
        var result = DeveloperResult()
        guard !token.isCancelled else { result.cancelled = true; return result }
        guard let base = try? FileSafety.canonicalRoot(home) else { return result }
        for (path, _) in targets {
            if token.isCancelled { result.cancelled = true; break }
            let target = base.appendingPathComponent(path)
            do {
                guard try FileSafety.metadataIfPresent(target) != nil else { continue }
                guard try FileSafety.canonicalRoot(target).path == target.path else { throw DonyError.unsafePath }
                var urls = [target]
                if path.hasSuffix("DerivedData") {
                    urls = []
                    for project in try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil) {
                        if ["ModuleCache.noindex", "SDKStatCaches.noindex", "CompilationCache.noindex"].contains(project.lastPathComponent) { urls.append(project); continue }
                        guard try FileSafety.fingerprint(project).isDirectory else { continue }
                        for generated in ["Build", "Index.noindex"] {
                            let child = project.appendingPathComponent(generated)
                            if try FileSafety.metadataIfPresent(child) != nil { urls.append(child) }
                        }
                    }
                }
                for url in urls {
                    try token.check()
                    guard try FileSafety.fingerprint(url).isDirectory, !CacheScopes.containsProject(url) else { continue }
                    try ProjectFileWalker.walk(root: url, token: token, limit: 1_000_000, timeout: 120, shouldDescend: {
                        !CacheScopes.isProtected($0) && !CacheScopes.containsProject($0)
                    }) { file, stamp in
                        guard stamp.isRegular, stamp.size > 0, !CacheScopes.isProtected(file) else { return }
                        let item = try FileCandidate.capture(url: file, root: url, kind: .developer, token: token)
                        result.items.append(item)
                        do {
                            try validate(item, home: base, runningTools: runningTools, now: now, token: token, days: days)
                            result.decisions[item.id] = CleanupDecision(true, "\(days)일 이상 변경 없는 재생성 가능 캐시")
                        } catch { result.decisions[item.id] = CleanupDecision(false, error.localizedDescription) }
                    }
                }
            } catch {
                if token.isCancelled { result.cancelled = true; break }
                result.issues.append(ScanIssue(path: target.path, error: error))
            }
        }
        result.items.sort { $0.bytes > $1.bytes }
        result.cancelled = result.cancelled || token.isCancelled
        if result.cancelled { result.decisions.removeAll() }
        return result
    }
    public static func validate(_ item: FileCandidate, home: URL = FileManager.default.homeDirectoryForCurrentUser, runningTools: Set<String>, now: Date = Date(), token: ScanToken = ScanToken(), requireOld: Bool = true, days: Int = 7) throws {
        try token.check()
        let base = try FileSafety.canonicalRoot(home)
        guard (1...3650).contains(days), !CacheScopes.isProtected(item.url) else { throw DonyError.unsafePath }
        let scopes = try targets.flatMap { path, _ -> [URL] in
            let target = base.appendingPathComponent(path)
            if !path.hasSuffix("DerivedData") { return [target] }
            guard try FileSafety.metadataIfPresent(target) != nil else { return [] }
            return try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).flatMap { project -> [URL] in
                if ["ModuleCache.noindex", "SDKStatCaches.noindex", "CompilationCache.noindex"].contains(project.lastPathComponent) { return [project] }
                return ["Build", "Index.noindex"].map { project.appendingPathComponent($0) }
            }
        }
        let known = scopes.contains { scope in
            item.fingerprint.isRegular ? item.root.path == scope.path && FileSafety.isWithin(item.url, root: scope) : item.url.path == scope.path
        }
        guard known, item.fingerprint.isRegular || item.fingerprint.isDirectory else { throw DonyError.unsafePath }
        if item.fingerprint.isRegular {
            var parent = item.url.deletingLastPathComponent()
            while true {
                guard !CacheScopes.containsProject(parent), !CacheScopes.isProtected(parent) else { throw DonyError.unsafePath }
                if parent.path == item.root.path { break }
                guard FileSafety.isWithin(parent, root: item.root) else { throw DonyError.unsafePath }
                parent.deleteLastPathComponent()
            }
        }
        guard !activeOwner(of: item.url, home: base, runningTools: runningTools) else { throw NSError(domain: "DonyClean", code: 1, userInfo: [NSLocalizedDescriptionKey: "관련 개발 도구 실행 중"]) }
        try FileSafety.validate(item, token: token)
        let cutoff = now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        func old(_ url: URL) throws -> Bool {
            let fp = try FileSafety.fingerprint(url)
            return ![".git", ".hg", ".svn", "checkouts"].contains(url.lastPathComponent) && (fp.isDirectory || fp.isRegular) && (!requireOld || Double(fp.seconds) + Double(fp.nanoseconds) / 1e9 <= cutoff)
        }
        guard try old(item.url) else { throw DonyError.changed }
        if item.fingerprint.isRegular { return }
        var issue: Error?
        guard let iterator = FileManager.default.enumerator(at: item.url, includingPropertiesForKeys: nil, errorHandler: { _, error in issue = error; return false }) else { throw DonyError.unsupported }
        var count = 0
        for case let child as URL in iterator {
            try token.check(); count += 1
            guard count <= 100_000, try old(child) else { throw DonyError.changed }
        }
        if let issue { throw issue }
        try FileSafety.validate(item, token: token)
    }
}
