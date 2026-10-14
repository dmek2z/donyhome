import Testing
import Foundation
@testable import DonyCore

@Suite struct WorkspaceTests {
    private func run(_ dir: URL, _ args: String...) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }
    /// home/.codex/worktrees/<name>/repo — 원격에 푸시된 깨끗한 체크아웃을 만든다.
    private func fixture(name: String = "job") throws -> (home: URL, workspace: URL, checkout: URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let remote = home.appendingPathComponent("remote.git")
        let workspace = home.appendingPathComponent(".codex/worktrees/" + name)
        let checkout = workspace.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try run(remote, "init", "--bare", "-b", "main")
        try run(workspace, "clone", remote.path, "repo")
        try Data("a".utf8).write(to: checkout.appendingPathComponent("a.txt"))
        try run(checkout, "add", "."); try run(checkout, "commit", "-m", "init"); try run(checkout, "push", "-u", "origin", "HEAD:main")
        return (home, workspace, checkout)
    }
    private let later = Date().addingTimeInterval(40 * 86400)
    private func candidate(_ f: (home: URL, workspace: URL, checkout: URL)) throws -> FileCandidate {
        try StaleWorkspaces.capture(f.workspace, root: f.workspace.deletingLastPathComponent(), token: ScanToken())
    }

    @Test func cleanPushedIdleWorkspaceIsRecommendedAndRecentOneIsKept() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.home) }
        let fresh = StaleWorkspaces.scan(home: f.home, token: ScanToken())
        #expect(fresh.items.count == 1)
        #expect(fresh.recommended.isEmpty)
        let idle = StaleWorkspaces.scan(home: f.home, token: ScanToken(), now: later)
        #expect(idle.recommended.count == 1)
        try StaleWorkspaces.validate(idle.items[0], home: f.home, requireOld: true, now: later)
    }
    @Test func uncommittedChangesAndUnpushedCommitsAreProtected() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.home) }
        let item = try candidate(f)
        try Data("dirty".utf8).write(to: f.checkout.appendingPathComponent("new.txt"))
        #expect(throws: (any Error).self) { try StaleWorkspaces.validate(item, home: f.home, requireOld: false, now: later) }
        try FileManager.default.removeItem(at: f.checkout.appendingPathComponent("new.txt"))
        try Data("b".utf8).write(to: f.checkout.appendingPathComponent("a.txt"))
        try run(f.checkout, "commit", "-am", "local only")
        let changed = try candidate(f)
        #expect(throws: (any Error).self) { try StaleWorkspaces.validate(changed, home: f.home, requireOld: false, now: later) }
        #expect(StaleWorkspaces.scan(home: f.home, token: ScanToken(), now: later).recommended.isEmpty)
    }
    @Test func regenerableIgnoredFoldersDoNotBlockButLargeLocalFilesDo() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.home) }
        try Data(".env\nnode_modules/\nnotes.bin\n".utf8).write(to: f.checkout.appendingPathComponent(".gitignore"))
        try run(f.checkout, "add", "."); try run(f.checkout, "commit", "-m", "ignore"); try run(f.checkout, "push", "origin", "HEAD:main")
        try FileManager.default.createDirectory(at: f.checkout.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10_000).write(to: f.checkout.appendingPathComponent("node_modules/pkg/index.js"))
        try Data("SECRET=1".utf8).write(to: f.checkout.appendingPathComponent(".env"))
        #expect(StaleWorkspaces.scan(home: f.home, token: ScanToken(), now: later).recommended.count == 1)
        try Data(repeating: 2, count: 6_000_000).write(to: f.checkout.appendingPathComponent("notes.bin"))
        #expect(StaleWorkspaces.scan(home: f.home, token: ScanToken(), now: later).recommended.isEmpty)
    }
    @Test func activeWorkspaceAndPathEscapesAreRejected() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.home) }
        #expect(throws: (any Error).self) { try StaleWorkspaces.requireSafe(f.workspace, active: [f.checkout.path], now: later, requireOld: true, token: ScanToken()) }
        #expect(throws: (any Error).self) { try StaleWorkspaces.requireSafe(f.workspace, active: nil, now: later, requireOld: true, token: ScanToken()) }
        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: other) }
        let outside = try StaleWorkspaces.capture(other, root: other.deletingLastPathComponent(), token: ScanToken())
        #expect(throws: (any Error).self) { try StaleWorkspaces.validate(outside, home: f.home, requireOld: false) }
    }
}

@Suite struct CLIProcessPolicyTests {
    private func process(_ name: String, path: String, cpu: Double?, memory: Int64 = 10_000_000, age: Double = 3600, uid: UInt32 = 501, pid: Int32 = 5000) -> ProcessReading {
        ProcessReading(pid: pid, uid: uid, startSeconds: UInt64(Date().timeIntervalSince1970 - age), startMicroseconds: 0, name: name, path: path, memoryBytes: memory, cpuNanos: nil, cpuPercent: cpu)
    }
    @Test func runawayAndIdleCLIProcessesAreFoundAndProtectedOnesAreNot() {
        let list = [
            process("grok", path: "/Users/u/.grok/bin/grok", cpu: 81, age: 4000, pid: 6001),
            process("node", path: "/opt/homebrew/bin/node", cpu: 0, memory: 400_000_000, age: 8 * 3600, pid: 6002),
            process("new", path: "/opt/homebrew/bin/new", cpu: 90, age: 120, pid: 6003),
            process("zsh", path: "/bin/zsh", cpu: 90, age: 9000, pid: 6004),
            process("claude", path: "/Users/u/.local/bin/claude", cpu: 90, age: 9000, pid: 6005),
            process("Helper", path: "/Applications/Foo.app/Contents/MacOS/Helper", cpu: 90, age: 9000, pid: 6006),
            process("other", path: "/Users/u/bin/other", cpu: 90, age: 9000, uid: 0, pid: 6007),
            process("self", path: "/Users/u/bin/self", cpu: 90, age: 9000, pid: 6008)
        ]
        let found = CLIProcessPolicy.findings(list, currentUID: 501, ownPID: 6008).map(\.process.name)
        #expect(found == ["grok", "node"])
    }
}
