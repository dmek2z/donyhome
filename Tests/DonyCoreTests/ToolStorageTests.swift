import Foundation
import Testing
@testable import DonyCore

@Suite final class ToolStorageTests {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let now = Date()
    init() throws { try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: home) }
    @discardableResult func file(_ path: String, days: Double = 20) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("12345".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86400)], ofItemAtPath: url.path)
        return url
    }
    func scan(_ tools: Set<AITool>, running: Set<AITool> = [], token: ScanToken = ScanToken()) -> ToolStorageResult {
        ToolStorage.scan(tools: tools, home: home, runningTools: running, days: 14, token: token, now: now)
    }
    @Test func findsEditorAndOrchestratorCachesBeyondChatGPTAndClaude() throws {
        try file("Library/Caches/Cursor/a")
        try file("Library/Caches/Windsurf/b")
        try file("Library/Logs/Orca/c.log")
        let result = scan([.cursor, .windsurf, .orca])
        #expect(result.items.count == 3)
        #expect(result.eligible.count == 3)
        #expect(result.totalBytes == 15)
        #expect(Set(result.items.flatMap { $0.owners }) == [.cursor, .windsurf, .orca])
    }
    @Test func discoversCLIArtifactsButKeepsSessionsCredentialsAndDatabases() throws {
        try file(".codex/log/old.log")
        try file(".claude/debug/old.txt")
        try file(".cache/opencode/cache.dat")
        try file(".codex/sessions/old.jsonl")
        try file(".codex/auth.json")
        try file(".claude/projects/history.jsonl")
        try file(".cache/opencode/auth.json")
        try file(".cache/opencode/state.sqlite")
        try file(".cache/opencode/sessions/transcript.jsonl")
        let result = scan([.codex, .claude, .opencode])
        #expect(Set(result.items.map { $0.candidate.name }) == ["old.log", "old.txt", "cache.dat"])
        #expect(result.eligible.count == 3)
    }
    @Test func sharedEditorCacheIsCountedOnceAndProtectedByAnyOwner() throws {
        try file("Library/Application Support/Code/Cache/data")
        let result = scan([.vscode, .copilot], running: [.vscode])
        #expect(result.items.count == 1)
        #expect(result.totalBytes == 5)
        #expect(result.items.first?.owners == [.vscode, .copilot])
        #expect(result.eligible.isEmpty)
        #expect(scan([.copilot], running: [.vscode]).eligible.isEmpty)
    }
    @Test func recentAndRunningFilesRemainVisibleButNotSelectable() throws {
        try file("Library/Caches/Cursor/old")
        try file("Library/Caches/Cursor/new", days: 0)
        #expect(scan([.cursor]).eligible.map { $0.candidate.name } == ["old"])
        let running = scan([.cursor], running: [.cursor])
        #expect(running.items.count == 2)
        #expect(running.eligible.isEmpty)
    }
    @Test func revalidatesLiveToolAgeAndFingerprintBeforeMovement() throws {
        let path = try file("Library/Caches/Cursor/old")
        let item = try #require(scan([.cursor]).eligible.first)
        try ToolStorage.validate(item, home: home, runningTools: [], days: 14, token: ScanToken(), now: now)
        #expect(throws: (any Error).self) { try ToolStorage.validate(item, home: home, runningTools: [.cursor], days: 14, token: ScanToken(), now: now) }
        #expect(throws: (any Error).self) { try ToolStorage.validate(item, home: home, runningTools: [], days: 30, token: ScanToken(), now: now) }
        try Data("changed".utf8).write(to: path)
        #expect(throws: (any Error).self) { try ToolStorage.validate(item, home: home, runningTools: [], days: 14, token: ScanToken(), now: now) }
    }
    @Test func ignoresLinksAndNestedProjectSources() throws {
        let source = try file("Library/Caches/Cursor/repo/package.json")
        try file("Library/Caches/Cursor/repo/src/app.swift")
        try file("Library/Caches/Cursor/keep")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/Cursor/link"), withDestinationURL: source)
        #expect(scan([.cursor]).items.map { $0.candidate.name } == ["keep"])
    }
    @Test func symlinkedProviderDirectoryIsRejected() throws {
        let target = try file("Elsewhere/cache/a").deletingLastPathComponent()
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/Cursor"), withDestinationURL: target)
        let result = scan([.cursor])
        #expect(result.items.isEmpty)
        #expect(!result.issues.isEmpty)
    }
    @Test func cancellationInvalidatesTheWholeCleanupPlan() throws {
        try file("Library/Caches/Cursor/old")
        let token = ScanToken(); token.cancel()
        let result = scan([.cursor], token: token)
        #expect(result.cancelled)
        #expect(result.eligible.isEmpty)
    }
    @Test func protectsCredentialsWithCaseVariations() throws {
        try file("Library/Caches/Cursor/AUTH.JSON")
        try file("Library/Caches/Cursor/Agents.md")
        #expect(scan([.cursor]).items.isEmpty)
    }
    @Test func validatesOnlyTheInspectedFileWhenNewCacheArrives() throws {
        let old = try file("Library/Caches/Cursor/old")
        let item = try #require(scan([.cursor]).eligible.first)
        let new = try file("Library/Caches/Cursor/new", days: 0)
        try ToolStorage.validate(item, home: home, runningTools: [], days: 14, token: ScanToken(), now: now)
        #expect(item.candidate.url.lastPathComponent == old.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: new.path))
    }
    @Test func sustainedPressureRequestsTaskReviewWithCooldown() {
        #expect(!DevelopmentPressurePolicy.shouldReview(pressure: .normal, duration: 100, sinceLastReview: 1000))
        #expect(!DevelopmentPressurePolicy.shouldReview(pressure: .warning, duration: 29, sinceLastReview: 1000))
        #expect(DevelopmentPressurePolicy.shouldReview(pressure: .warning, duration: 30, sinceLastReview: 600))
        #expect(!DevelopmentPressurePolicy.shouldReview(pressure: .critical, duration: 100, sinceLastReview: 599))
    }
    @Test func closedOldLogsCanBeReviewedWhileActiveCachesRemainProtected() throws {
        try file("Library/Caches/Codex/old")
        try file("Library/Logs/com.openai.codex/old.log")
        let closed = OpenFileSnapshot(paths: [], complete: true)
        let result = ToolStorage.scan(tools: [.codex], home: home, runningTools: [.codex], days: 14, token: ScanToken(), now: now, openFiles: closed)
        #expect(result.eligible.map { $0.candidate.name } == ["old.log"])
        #expect(ToolStorage.scan(tools: [.codex], home: home, runningTools: [.codex], days: 14, token: ScanToken(), now: now, openFiles: OpenFileSnapshot(paths: [], complete: false)).eligible.isEmpty)
        let item = try #require(result.eligible.first)
        #expect(throws: (any Error).self) {
            try ToolStorage.validate(item, home: home, runningTools: [.codex], days: 14, token: ScanToken(), now: now, openFiles: OpenFileSnapshot(paths: [item.id], complete: true))
        }
        #expect(ToolStorage.scan(tools: [.codex], home: home, runningTools: [], days: 14, token: ScanToken(), now: now, openFiles: OpenFileSnapshot(paths: [], identities: [item.candidate.fingerprint.identity], complete: true)).eligible.allSatisfy { $0.id != item.id })
    }
    @Test func toolTraversalLimitMarksPartialMeasuredResults() throws {
        for i in 0..<10 { try file("Library/Caches/Cursor/\(i)") }
        let result = ToolStorage.scan(tools: [.cursor], home: home, runningTools: [], days: 14, token: ScanToken(), now: now, limit: 3)
        #expect(result.incompleteTools.contains(.cursor))
        #expect(!result.issues.isEmpty)
        #expect(result.items.count < 10)
    }

}
