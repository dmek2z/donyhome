import Testing
import Foundation
@testable import DonyCore

@Suite final class ProjectCleanupTests {
    let root: URL
    let now = Date()
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func project(_ name: String, days: Double) throws -> LinkedProject {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.appendingPathComponent(".next"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url.appendingPathComponent("package.json"))
        try Data("source".utf8).write(to: url.appendingPathComponent("app.ts"))
        try Data("generated".utf8).write(to: url.appendingPathComponent(".next/cache"))
        for path in ["package.json", "app.ts", ".next/cache", ".next", ""] {
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86400)], ofItemAtPath: url.appendingPathComponent(path).path)
        }
        return LinkedProject(tool: .cursor, path: url.path)
    }
    @Test func contextScopeIsExplicitAndProtectsSourceAndLiveProjects() throws {
        let old = try project("context", days: 20)
        let folder = URL(fileURLWithPath: old.path)
        let context = folder.appendingPathComponent("CLAUDE.md")
        try Data("project instructions".utf8).write(to: context)
        for url in [context, folder] { try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-20 * 86400)], ofItemAtPath: url.path) }
        let generated = ProjectCleanup.scan(projects: [old], days: 14, scope: .generated, activePaths: [], runningTools: [], now: now, token: ScanToken())
        #expect(!generated.items.contains { $0.url == context })
        let result = ProjectCleanup.scan(projects: [old], days: 14, scope: .context, activePaths: [], runningTools: [], now: now, token: ScanToken())
        #expect(result.items.map(\.name) == ["CLAUDE.md"])
        let candidate = try #require(result.items.first)
        try ProjectCleanup.validate(candidate, project: old, days: 14, scope: .context, activePaths: [], runningTools: [], now: now, token: ScanToken())
        #expect(try String(contentsOf: folder.appendingPathComponent("app.ts")) == "source")
        #expect(ProjectCleanup.scan(projects: [old], days: 14, scope: .context, activePaths: [old.path], runningTools: [], now: now, token: ScanToken()).items.isEmpty)
        #expect(ProjectCleanup.scan(projects: [old], days: 14, scope: .context, activePaths: [], runningTools: [.cursor], now: now, token: ScanToken()).items.isEmpty)
    }
    @Test func contextScopeNeverIncludesNestedWorktrees() throws {
        let old = try project("nested", days: 20)
        let folder = URL(fileURLWithPath: old.path)
        let checkout = folder.appendingPathComponent(".claude/worktrees/task")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: checkout.appendingPathComponent("app.ts"))
        try Data("{}".utf8).write(to: checkout.appendingPathComponent("package.json"))
        for path in [".claude/worktrees/task/app.ts", ".claude/worktrees/task/package.json", ".claude/worktrees/task", ".claude/worktrees", ".claude", ""] {
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-20 * 86400)], ofItemAtPath: folder.appendingPathComponent(path).path)
        }
        let result = ProjectCleanup.scan(projects: [old], days: 14, scope: .context, activePaths: [], runningTools: [], now: now, token: ScanToken())
        #expect(result.items.isEmpty)
        #expect(try String(contentsOf: checkout.appendingPathComponent("app.ts")) == "source")
    }
    @Test func retentionUsesNewestDescendantAndCustomDays() throws {
        let old = try project("old", days: 8)
        #expect(ProjectCleanup.scan(projects: [old], days: 14, scope: .generated, activePaths: [], runningTools: [], now: now, token: ScanToken()).items.isEmpty)
        let eligible = ProjectCleanup.scan(projects: [old], days: 7, scope: .generated, activePaths: [], runningTools: [], now: now, token: ScanToken())
        #expect(eligible.items.map(\.name) == [".next"])
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: URL(fileURLWithPath: old.path).appendingPathComponent("app.ts").path)
        #expect(ProjectCleanup.scan(projects: [old], days: 7, scope: .wholeProject, activePaths: [], runningTools: [], now: now, token: ScanToken()).items.isEmpty)
    }
    @Test func wholeProjectIsExplicitAndProtectsActiveAndRecentlyUsedProjects() throws {
        let old = try project("old", days: 20)
        let whole = ProjectCleanup.scan(projects: [old], days: 14, scope: .wholeProject, activePaths: [], runningTools: [], now: now, token: ScanToken())
        #expect(whole.items.count == 1)
        #expect(whole.items.first?.url.lastPathComponent == "old")
        for (active, running, activity) in [([old.path + "/src"], Set<AITool>(), Date?.none), ([], Set([AITool.cursor]), Date?.none), ([], Set<AITool>(), Optional(now))] {
            let linked = LinkedProject(tool: .cursor, path: old.path, lastActivity: activity)
            #expect(ProjectCleanup.scan(projects: [linked], days: 14, scope: .wholeProject, activePaths: active, runningTools: running, now: now, token: ScanToken()).items.isEmpty)
        }
    }
    @Test func refusesUnmarkedRootsLinksAndCancelledPlans() throws {
        let unmarked = LinkedProject(tool: .codex, path: root.path)
        #expect(ProjectCleanup.scan(projects: [unmarked], days: 1, scope: .wholeProject, activePaths: [], runningTools: [], now: now, token: ScanToken()).items.isEmpty)
        let old = try project("old", days: 20)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: URL(fileURLWithPath: old.path))
        #expect(ProjectCleanup.scan(projects: [LinkedProject(tool: .codex, path: alias.path)], days: 1, scope: .wholeProject, activePaths: [], runningTools: [], now: now, token: ScanToken()).items.isEmpty)
        let token = ScanToken(); token.cancel()
        let cancelled = ProjectCleanup.scan(projects: [old], days: 1, scope: .wholeProject, activePaths: [], runningTools: [], now: now, token: token)
        #expect(cancelled.cancelled)
        #expect(cancelled.items.isEmpty)
    }
    @Test func revalidationCatchesFreshSourceAfterGeneratedScan() throws {
        let old = try project("old", days: 20)
        let scan = ProjectCleanup.scan(projects: [old], days: 14, scope: .generated, activePaths: [], runningTools: [], now: now, token: ScanToken())
        let item = try #require(scan.items.first)
        try Data("new source".utf8).write(to: URL(fileURLWithPath: old.path).appendingPathComponent("app.ts"))
        expectThrows(try ProjectCleanup.validate(item, project: old, days: 14, scope: .generated, activePaths: [], runningTools: [], now: now, token: ScanToken()))
    }
    @Test func parsesHistoryMetadataWithoutTreatingOtherStringsAsProjects() throws {
        let old = try project("old", days: 20)
        let data = try JSONSerialization.data(withJSONObject: ["cwd": old.path, "message": "/tmp/do-not-use"])
        #expect(ProjectDiscovery.paths(in: data) == [old.path])
        #expect(ProjectDiscovery.paths(in: Data("{\"message\":\"/tmp/ignore\"}".utf8)).isEmpty)
    }
    @Test func generatedScopeAlsoProtectsRunningGUIOwnersWithUnknownCWD() throws {
        let old = try project("open-project", days: 20)
        #expect(ProjectCleanup.scan(projects: [old], days: 14, scope: .generated, activePaths: [], runningTools: [.cursor], now: now, token: ScanToken()).items.isEmpty)
    }
    @Test func batchAllowsOwnDirectoryMovesButStillRejectsSourceDeletion() throws {
        let old = try project("batch", days: 20)
        let url = URL(fileURLWithPath: old.path)
        let extra = url.appendingPathComponent(".nuxt")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        try Data("generated".utf8).write(to: extra.appendingPathComponent("cache"))
        for path in [extra.appendingPathComponent("cache"), extra, url] { try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-20 * 86400)], ofItemAtPath: path.path) }
        let scan = ProjectCleanup.scan(projects: [old], days: 14, scope: .generated, activePaths: [], runningTools: [], now: now, token: ScanToken())
        #expect(scan.items.count == 2)
        let state = try ProjectCleanup.captureSourceState(project: old, removing: scan.items, token: ScanToken())
        let first = try #require(scan.items.first); let second = scan.items[1]
        // Simulate our own recoverable rename without touching the user's Trash.
        try FileManager.default.moveItem(at: first.url, to: root.appendingPathComponent("removed"))
        try ProjectCleanup.validate(second, project: old, days: 14, scope: .generated, activePaths: [], runningTools: [], now: now, token: ScanToken(), sourceState: state)
        try FileManager.default.removeItem(at: url.appendingPathComponent("app.ts"))
        expectThrows(try ProjectCleanup.validate(second, project: old, days: 14, scope: .generated, activePaths: [], runningTools: [], now: now, token: ScanToken(), sourceState: state))
    }
}
