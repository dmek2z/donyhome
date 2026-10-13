import Foundation
import Darwin
import Testing
@testable import DonyCore

@Suite struct ProjectInventoryTests {
    @Test func countsContextsSeparatelyFromDisposableGeneratedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["src", ".next", ".claude/agents"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        for (path, contents) in [("src/code.swift", "source"), (".next/cache", "generated"), ("CLAUDE.md", "instructions"), (".claude/agents/main.md", "agent")] { try Data(contents.utf8).write(to: root.appendingPathComponent(path)) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        let rows = ProjectInventory.inspect(projects: [LinkedProject(tool: .claude, path: root.path), LinkedProject(tool: .codex, path: root.path)], token: ScanToken())
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.tools == [.claude, .codex])
        #expect(row.files == 4)
        #expect(row.generatedBytes == 9)
        #expect(row.contextFiles == 2)
        #expect(row.contextBytes == 17)
        #expect(row.issues.isEmpty)
    }
    @Test func managedWorktreesAreVisibleButRemainProtectedFromFolderCleanup() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent(".codex/worktrees/id/project")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("gitdir: /managed/git".utf8).write(to: root.appendingPathComponent(".git"))
        let links = ProjectInventory.discoverManagedWorktrees(home: home, token: ScanToken())
        #expect(links.count == 1)
        #expect(links.first?.enabled == false)
        let row = try #require(ProjectInventory.inspect(projects: links, token: ScanToken()).first)
        #expect(row.managedWorktree)
        #expect(throws: (any Error).self) { try ProjectCleanup.projectRoot(root.path) }
    }
    @Test func metadataWalkerDoesNotOpenFIFOAndHonorsCancellationAndBounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(mkfifo(root.appendingPathComponent("pipe").path, 0o600) == 0)
        try Data("source".utf8).write(to: root.appendingPathComponent("code"))
        var regular = 0
        try ProjectFileWalker.walk(root: root, token: ScanToken()) { _, stamp in if stamp.isRegular { regular += 1 } }
        #expect(regular == 1)
        let cancelled = ScanToken(); cancelled.cancel()
        #expect(throws: (any Error).self) { try ProjectFileWalker.walk(root: root, token: cancelled) { _, _ in } }
        #expect(throws: (any Error).self) { try ProjectFileWalker.walk(root: root, token: ScanToken(), limit: 1) { _, _ in } }
    }

}
