import Foundation

public struct CacheInventoryGroup: Identifiable, Sendable {
    public var id: String { root.path }
    public let root: URL
    public let kind: CandidateKind
    public var bytes: Int64 = 0
    public var recommendedBytes: Int64 = 0
    public var files = 0
    public var incomplete = false
    public var status = ""
    public var protectedBytes: Int64 { max(0, bytes - recommendedBytes) }
    public var title: String {
        root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Application Support" ? root.deletingLastPathComponent().lastPathComponent + " · " + root.lastPathComponent : root.lastPathComponent
    }
}

public struct CacheCleanupResult: Sendable {
    public var files = ScanResult()
    public var decisions: [String: CleanupDecision] = [:]
    public var groups: [CacheInventoryGroup] = []
    public var measuredBytes: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    public var recommendedBytes: Int64 { files.totalBytes }
    public var protectedBytes: Int64 { max(0, measuredBytes - recommendedBytes) }
    public var rootInventoryIncomplete = false
    public var incomplete: Bool { rootInventoryIncomplete || groups.contains(where: \.incomplete) }
    public init() {}
}

public enum CacheCleanup {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, runningOwners: Set<String>, days: Int = 14, token: ScanToken, now: Date = Date(), limit: Int = 1_000_000, timeout: TimeInterval = 120, candidateLimit: Int = 20_000, progress: Scanner.Progress? = nil) -> CacheCleanupResult {
        var result = CacheCleanupResult()
        guard (1...3650).contains(days), !token.isCancelled else {
            result.files.cancelled = true; return result
        }
        let base: URL
        do { base = try FileSafety.canonicalRoot(home) }
        catch { result.rootInventoryIncomplete = true; result.files.issues.append(ScanIssue(path: home.path, error: error)); return result }
        var locations: [(URL, CandidateKind)] = []
        for (relative, kind) in [("Library/Caches", CandidateKind.cache), ("Library/Logs", .log)] {
            let root = base.appendingPathComponent(relative)
            do {
                guard try FileSafety.metadataIfPresent(root) != nil else { continue }
                guard try FileSafety.canonicalRoot(root).path == root.path else { throw DonyError.unsafePath }
                locations += try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).map { ($0, kind) }
            } catch { result.rootInventoryIncomplete = true; result.files.issues.append(ScanIssue(path: root.path, error: error)) }
        }
        for alias in CacheScopes.namedOwners.keys.sorted() {
            for child in ["Cache", "Code Cache", "GPUCache", "ShaderCache"] {
                let root = base.appendingPathComponent("Library/Application Support/" + alias + "/" + child)
                do {
                    if try FileSafety.metadataIfPresent(root) != nil { locations.append((root, .cache)) }
                } catch { result.rootInventoryIncomplete = true; result.files.issues.append(ScanIssue(path: root.path, error: error)) }
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        var identities = Set<String>()
        for (root, kind) in locations.sorted(by: { $0.0.path < $1.0.path }) {
            if token.isCancelled { break }
            var group = CacheInventoryGroup(root: root, kind: kind)
            do {
                guard result.files.visited < limit, Date() < deadline else { throw DonyError.scanLimit }
                let stamp = try FileSafety.fingerprint(root)
                if stamp.isRegular {
                    group.files = 1; group.bytes = max(0, stamp.size)
                    if identities.insert(stamp.identity).inserted {
                        let candidate = try FileCandidate.capture(url: root, root: root.deletingLastPathComponent(), kind: kind, token: token)
                        let decision = try CleanupPolicy(home: base, days: days).reason(for: candidate, now: now, runningBundleIDs: runningOwners, token: token)
                        group.status = decision.reason
                        if decision.isRecommended {
                            guard result.files.items.count < candidateLimit else { throw DonyError.scanLimit }
                            result.files.items.append(candidate); result.decisions[candidate.id] = decision; group.recommendedBytes = candidate.bytes }
                    } else { group.bytes = 0 }
                    result.groups.append(group); continue
                }
                guard root.lastPathComponent != "com.apple.Music", stamp.isDirectory,
                      try FileSafety.canonicalRoot(root).path == root.path, !CacheScopes.containsProject(root) else { throw DonyError.unsafePath }
                let policy = CleanupPolicy(home: base, days: days)
                let known = kind == .log || CacheScopes.isKnown(root: root, home: base)
                let running = policy.runningOwner(of: root.appendingPathComponent("_"), runningBundleIDs: runningOwners) != nil
                group.status = running ? "사용 중 · 보관" : !known ? "경로 미확인 · 보관" : "\(days)일 기준"
                let cutoff = now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
                try ProjectFileWalker.walk(root: root, token: token, limit: limit, timeout: timeout, shouldDescend: { directory in
                    if CacheScopes.isProtected(directory) || CacheScopes.containsProject(directory) {
                        group.incomplete = true; return false
                    }
                    return true
                }) { url, fingerprint in
                    result.files.visited += 1
                    guard result.files.visited <= limit, Date() < deadline else { throw DonyError.scanLimit }
                    if result.files.visited.isMultiple(of: 250) { progress?(result.files.visited, group.title) }
                    guard fingerprint.isRegular, identities.insert(fingerprint.identity).inserted else { return }
                    group.files += 1; group.bytes += max(0, fingerprint.size)
                    guard known, !running, !CacheScopes.isProtected(url),
                          Double(fingerprint.seconds) + Double(fingerprint.nanoseconds) / 1e9 <= cutoff,
                          kind != .log || CacheScopes.isLog(url) else { return }
                    guard result.files.items.count < candidateLimit else { throw DonyError.scanLimit }
                    let candidate = try FileCandidate.capture(url: url, root: root, kind: kind, token: token)
                    let decision = try policy.reason(for: candidate, now: now, runningBundleIDs: runningOwners, token: token)
                    guard decision.isRecommended else { return }
                    result.files.items.append(candidate); result.decisions[candidate.id] = decision
                    group.recommendedBytes += candidate.bytes
                }
            } catch {
                group.incomplete = true; group.status = "일부 결과 · 확인 필요"
                if !token.isCancelled && result.files.issues.count < 100 { result.files.issues.append(ScanIssue(path: root.path, error: error)) }
            }
            result.groups.append(group)
        }
        result.files.cancelled = token.isCancelled
        if result.files.cancelled { result.files.items.removeAll(); result.decisions.removeAll(); for i in result.groups.indices { result.groups[i].recommendedBytes = 0 } }
        result.groups.sort { $0.bytes > $1.bytes }
        result.files.items.sort { $0.bytes > $1.bytes }
        return result
    }
}

// Known cache namespaces only; support folders outside cache leaves stay out of scope.
enum CacheScopes {
    static let namedOwners: [String: Set<String>] = [
        "Google": ["com.google.Chrome", "Google Chrome"], "Aside": ["Aside"],
        "Codex": ["com.openai.codex", "Codex"], "ChatGPT": ["com.openai.chat", "ChatGPT"],
        "Claude": ["com.anthropic.claudefordesktop", "Claude"],
        "Cursor": ["com.todesktop.230313mzl4w4u92", "Cursor"],
        "Code": ["com.microsoft.VSCode", "Code"], "VS Code": ["com.microsoft.VSCode"],
        "Windsurf": ["com.exafunction.windsurf", "Windsurf"],
        "Slack": ["com.tinyspeck.slackmacgap", "Slack"], "Slack.app": ["com.tinyspeck.slackmacgap", "Slack"],
        "Figma": ["com.figma.Desktop", "Figma"], "pnpm": ["pnpm", "pnpx", "node"],
        "pip": ["pip", "pip3", "python", "python3"], "Homebrew": ["brew", "ruby"], "Yarn": ["yarn", "node"]
    ]
    static let protectedNames: Set<String> = Set(ProjectCleanup.markers.map { $0.lowercased() }).union([
        "auth.json", "credentials.json", "tokens.json", "settings.json", "config.json", "config.toml",
        "agents.md", "claude.md", "gemini.md", "memory.md", "sessions", "archived_sessions", "worktrees",
        "cookies", "history", "login data", "web data", "local storage", "session storage", "indexeddb", "checkouts", "drivefs"
    ])
    static func isProtected(_ url: URL) -> Bool {
        url.pathComponents.contains { part in
            let value = part.lowercased()
            return protectedNames.contains(value) || value.contains("credential") || value.hasPrefix("auth.") ||
                value.hasSuffix(".jsonl") || [".db", ".sqlite", ".sqlite3", ".vscdb"].contains { ext in
                    value.hasSuffix(ext) || ["-wal", "-shm", "-journal"].contains { value.hasSuffix(ext + $0) }
                }
        }
    }
    static func containsProject(_ url: URL) -> Bool {
        ProjectCleanup.markers.contains { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }
    }
    static func isLog(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".log") || name.hasSuffix(".log.gz") || name.range(of: #"\.log\.\d+$"#, options: .regularExpression) != nil
    }
    static func owner(of url: URL, home: URL) -> String? {
        for relative in ["Library/Caches", "Library/Logs", "Library/Application Support"] {
            let root = home.appendingPathComponent(relative)
            if FileSafety.isWithin(url, root: root) {
                return String(url.path.dropFirst(root.path.count + 1)).split(separator: "/").first.map(String.init)
            }
        }
        return nil
    }
    static func isKnown(root: URL, home: URL) -> Bool {
        guard let owner = owner(of: root, home: home) else { return false }
        return namedOwners[owner] != nil || CleanupPolicy.cacheOwners.contains(owner) ||
            ["com.openai.codex", "com.openai.chat", "com.anthropic.claudefordesktop", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf"].contains(owner)
    }
    static func allowedScope(root: URL, home: URL, kind: CandidateKind) -> Bool {
        let outer = home.appendingPathComponent(kind == .cache ? "Library/Caches" : "Library/Logs")
        if root.path == outer.path || root.deletingLastPathComponent().path == outer.path { return true }
        let support = home.appendingPathComponent("Library/Application Support")
        return kind == .cache && root.deletingLastPathComponent().deletingLastPathComponent().path == support.path &&
            namedOwners[root.deletingLastPathComponent().lastPathComponent] != nil && ["Cache", "Code Cache", "GPUCache", "ShaderCache"].contains(root.lastPathComponent)
    }
}
