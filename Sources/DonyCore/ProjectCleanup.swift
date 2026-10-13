import Foundation
import CryptoKit

public struct ProjectSourceState: Sendable {
    let root: URL
    let excluded: Set<String>
    let ignoredDirectoryDates: Set<String>
    let stamp: String
}

public enum ProjectCleanupScope: String, Codable, CaseIterable, Sendable {
    case generated, context, wholeProject
    public var title: String { switch self { case .generated: return "빌드 · 캐시만"; case .context: return "프로젝트 AI 컨텍스트"; case .wholeProject: return "프로젝트 전체 · 소스 포함" } }
}
public struct LinkedProject: Identifiable, Codable, Sendable {
    public var id: String { (discovered ? "history:" : "manual:") + tool.id + ":" + path }
    public let tool: AITool
    public let path: String
    public var lastActivity: Date?
    public var enabled: Bool
    public var discovered: Bool
    public init(tool: AITool, path: String, lastActivity: Date? = nil, enabled: Bool = true, discovered: Bool = false) {
        self.tool = tool; self.path = path; self.lastActivity = lastActivity; self.enabled = enabled; self.discovered = discovered
    }
}
public enum ProjectCleanup {
    // Names with a documented generated purpose; generic build/dist folders may contain user files.
    public static let generatedPaths = [".next", ".nuxt", ".svelte-kit", ".parcel-cache", ".turbo", "node_modules/.cache", ".pytest_cache", ".mypy_cache", ".ruff_cache"]
    public static let markers = [".git", "package.json", "Package.swift", "pyproject.toml", "Cargo.toml", "go.mod", "CMakeLists.txt"]
    public static func projectRoot(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = try FileSafety.canonicalRoot(url)
        guard try FileSafety.fingerprint(url).isDirectory, FileSafety.allowedRoot(base, kind: .project), try FileSafety.fingerprint(base).isDirectory,
              ![home.path, home.appendingPathComponent("Documents").path, home.appendingPathComponent("Desktop").path, home.appendingPathComponent("Downloads").path].contains(base.path),
              !["Library", ".codex", ".claude", ".hermes", ".cursor", ".orca"].contains(base.lastPathComponent),
              !base.path.contains("/.codex/worktrees/"),
              markers.contains(where: { FileManager.default.fileExists(atPath: base.appendingPathComponent($0).path) }) else { throw DonyError.unsafePath }
        return base
    }
    public static func latestChange(_ root: URL, token: ScanToken, ignoringDirectoryDates: Set<String> = []) throws -> Date {
        let fp = try FileSafety.fingerprint(root)
        var latest = ignoringDirectoryDates.contains(root.path) ? 0 : Double(fp.seconds) + Double(fp.nanoseconds) / 1e9
        var failure: Error?
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in failure = error; return false }) else { throw DonyError.unsupported }
        var count = 0
        for case let url as URL in iterator {
            try token.check(); count += 1
            guard count <= 100_000 else { throw DonyError.scanLimit }
            let child = try FileSafety.fingerprint(url)
            guard child.isRegular || child.isDirectory else { throw DonyError.unsafePath }
            if !child.isDirectory || !ignoringDirectoryDates.contains(url.path) { latest = max(latest, Double(child.seconds) + Double(child.nanoseconds) / 1e9) }
        }
        if let failure { throw failure }
        return Date(timeIntervalSince1970: latest)
    }
    private static func eligible(_ project: LinkedProject, days: Int, scope: ProjectCleanupScope, activePaths: [String], runningTools: Set<AITool>, now: Date, token: ScanToken, ignoringDirectoryDates: Set<String> = []) throws -> URL {
        try token.check()
        guard project.enabled, (1...3650).contains(days) else { throw DonyError.unsafePath }
        let root = try projectRoot(project.path)
        guard !activePaths.contains(where: {
            let active = URL(fileURLWithPath: $0).resolvingSymlinksInPath()
            let comparableRoot = root.resolvingSymlinksInPath()
            return active.path == comparableRoot.path || FileSafety.isWithin(active, root: comparableRoot)
        }) else { throw DonyError.protectedProcess }
        // GUI editors do not always expose their open workspace through cwd.
        // Both cleanup scopes exclude projects owned by a running tool.
        if runningTools.contains(project.tool) { throw DonyError.protectedProcess }
        if scope == .wholeProject, (try? FileSafety.fingerprint(root.appendingPathComponent(".git")))?.isRegular == true { throw DonyError.unsupported }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        guard (project.lastActivity ?? .distantPast) <= cutoff, try latestChange(root, token: token, ignoringDirectoryDates: ignoringDirectoryDates) <= cutoff else { throw DonyError.changed }
        return root
    }
    public static func scan(projects: [LinkedProject], days: Int, scope: ProjectCleanupScope, activePaths: [String], runningTools: Set<AITool>, now: Date = Date(), token: ScanToken, progress: Scanner.Progress? = nil) -> ScanResult {
        var result = ScanResult()
        for project in projects where project.enabled {
            if token.isCancelled { break }
            result.visited += 1; progress?(result.visited, URL(fileURLWithPath: project.path).lastPathComponent)
            do {
                let root = try eligible(project, days: days, scope: scope, activePaths: activePaths, runningTools: runningTools, now: now, token: token)
                let paths = scope == .wholeProject ? [root] : (scope == .context ? ProjectInventory.contextPaths : generatedPaths).map { root.appendingPathComponent($0) }
                for url in paths {
                    try token.check()
                    guard try FileSafety.metadataIfPresent(url) != nil else { continue }
                    let item = try FileCandidate.capture(url: url, root: scope == .wholeProject ? root.deletingLastPathComponent() : root, kind: .project, token: token)
                    try validate(item, project: project, days: days, scope: scope, activePaths: activePaths, runningTools: runningTools, now: now, token: token)
                    if item.bytes > 0 { result.items.append(item) }
                }
            } catch {
                if !token.isCancelled && result.issues.count < 100 { result.issues.append(ScanIssue(path: project.path, error: error)) }
            }
        }
        result.cancelled = token.isCancelled
        if result.cancelled { result.items.removeAll() }
        result.items = RecommendedActions.plan(cleanup: result.items, duplicates: []).items
        return result
    }
    public static func validate(_ item: FileCandidate, project: LinkedProject, days: Int, scope: ProjectCleanupScope, activePaths: [String], runningTools: Set<AITool>, now: Date = Date(), token: ScanToken, sourceState: ProjectSourceState? = nil) throws {
        if let state = sourceState {
            guard scope != .wholeProject, try projectRoot(project.path).path == state.root.path,
                  try sourceStamp(root: state.root, excluded: state.excluded, ignoringDirectoryDates: state.ignoredDirectoryDates, token: token) == state.stamp else { throw DonyError.changed }
        }
        let root = try eligible(project, days: days, scope: scope, activePaths: activePaths, runningTools: runningTools, now: now, token: token, ignoringDirectoryDates: sourceState?.ignoredDirectoryDates ?? [])
        let allowed = scope == .wholeProject ? item.url.path == root.path : (scope == .context ? ProjectInventory.contextPaths : generatedPaths).contains { root.appendingPathComponent($0).path == item.url.path }
        guard item.kind == .project, allowed, (item.fingerprint.isDirectory || scope == .context && item.fingerprint.isRegular) else { throw DonyError.unsafePath }
        if scope == .context, item.fingerprint.isDirectory {
            guard let iterator = FileManager.default.enumerator(at: item.url, includingPropertiesForKeys: nil) else { throw DonyError.unsupported }
            var count = 0
            for case let child as URL in iterator {
                try token.check(); count += 1
                guard count <= 10_000, !markers.contains(child.lastPathComponent) else { throw DonyError.unsafePath }
            }
        }
        try FileSafety.validate(item, token: token)
    }
    public static func captureSourceState(project: LinkedProject, removing items: [FileCandidate], scope: ProjectCleanupScope = .generated, token: ScanToken) throws -> ProjectSourceState {
        let root = try projectRoot(project.path)
        let paths = Set(items.map { $0.url.path })
        guard items.allSatisfy({ item in item.kind == .project && (scope == .context ? ProjectInventory.contextPaths : generatedPaths).contains { root.appendingPathComponent($0).path == item.url.path } }) else { throw DonyError.unsafePath }
        let parents = Set(items.map { $0.url.deletingLastPathComponent().path })
        return ProjectSourceState(root: root, excluded: paths, ignoredDirectoryDates: parents, stamp: try sourceStamp(root: root, excluded: paths, ignoringDirectoryDates: parents, token: token))
    }
    private static func sourceStamp(root: URL, excluded: Set<String>, ignoringDirectoryDates: Set<String>, token: ScanToken) throws -> String {
        var rows: [String] = []
        func row(_ url: URL) throws {
            let fp = try FileSafety.fingerprint(url)
            guard fp.isDirectory || fp.isRegular else { throw DonyError.unsafePath }
            let age = fp.isDirectory && ignoringDirectoryDates.contains(url.path) ? "" : "\(fp.seconds):\(fp.nanoseconds)"
            rows.append("\(url.path):\(fp.identity):\(fp.mode):\(fp.isDirectory ? 0 : fp.size):\(age)")
        }
        try row(root)
        var failure: Error?
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in failure = error; return false }) else { throw DonyError.unsupported }
        var count = 0
        for case let url as URL in iterator {
            try token.check(); count += 1
            guard count <= 100_000 else { throw DonyError.scanLimit }
            if excluded.contains(url.path) { iterator.skipDescendants(); continue }
            try row(url)
        }
        if let failure { throw failure }
        var hash = SHA256()
        for row in rows.sorted() { hash.update(data: Data((row + "\n").utf8)) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
