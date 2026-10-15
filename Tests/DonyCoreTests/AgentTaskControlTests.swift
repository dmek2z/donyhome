import Foundation
import Darwin
import Testing
@testable import DonyCore

private final class AgentTaskFixture {
    var rows: [ProcessReading]
    var stopped = Set<Int32>()
    var signals: [(Int32, Int32)] = []
    var saved: [OwnedAgentTask] = []
    var failSignal: ((Int32, Int32) -> Bool)?
    var afterSignal: ((Int32, Int32) -> Void)?
    var unknownCWD = Set<Int32>()
    var directories: [Int32: String] = [:]
    init(_ rows: [ProcessReading]) { self.rows = rows }
    func callbacks() -> AgentTaskCallbacks {
        AgentTaskCallbacks(snapshot: { self.rows }, workingDirectory: { self.unknownCWD.contains($0.pid) ? nil : (self.directories[$0.pid] ?? "/Users/test/project") }, rootTool: { AgentTaskControl.cliTool($0) }, verifyIdentity: { original in
            guard self.rows.contains(where: { ProcessPolicy.sameIdentity($0, original) }) else { throw AgentTaskError.changed }
        }, isStopped: { self.stopped.contains($0.pid) }, signal: { pid, value in
            self.signals.append((pid, value))
            if self.failSignal?(pid, value) == true { throw AgentTaskError.partial("injected failure") }
            if value == SIGSTOP { self.stopped.insert(pid) }
            if value == SIGCONT { self.stopped.remove(pid) }
            self.afterSignal?(pid, value)
        }, persist: { self.saved = $0 })
    }
    func control(owned: [OwnedAgentTask] = []) -> AgentTaskControl {
        AgentTaskControl(currentUID: 501, ownPID: 999, callbacks: callbacks(), owned: owned)
    }
    func discover() -> [AgentTaskGroup] {
        AgentTaskControl.discover(rows, currentUID: 501, ownPID: 999, workingDirectory: callbacks().workingDirectory, rootTool: callbacks().rootTool)
    }
}
@Suite struct AgentTaskControlTests {
    func process(_ pid: Int32, parent: Int32 = 1, name: String = "claude", uid: UInt32 = 501, start: UInt64 = 100, path: String? = nil, hint: String? = nil) -> ProcessReading {
        ProcessReading(pid: pid, uid: uid, startSeconds: start, startMicroseconds: 5, name: name, path: path ?? "/usr/local/bin/" + name, memoryBytes: 1024, cpuNanos: nil, cpuPercent: nil, parentPID: parent, toolHint: hint)
    }
    @Test func acceptsExplicitCLIWithWorkerButNeverArbitraryNodeOrGUI() {
        let root = process(200)
        let child = process(201, parent: 200, name: "node")
        let fixture = AgentTaskFixture([root, child, process(300, name: "node"), process(400, name: "claude", path: "/Applications/Claude.app/Contents/MacOS/claude")])
        let tasks = fixture.discover()
        #expect(tasks.count == 1)
        #expect(tasks.first?.members.map(\.pid) == [200, 201])
        let node = process(500, name: "node", hint: "claude")
        #expect(AgentTaskControl.cliTool(node) == nil)
        #expect(AgentTaskControl.cliTool(node, arguments: ["node", "/opt/node_modules/@anthropic-ai/claude-code/cli.js"]) == .claude)
        #expect(AgentTaskControl.cliTool(node, arguments: ["node", "--eval", "claude"]) == nil)
        #expect(AgentTaskControl.cliTool(process(600, name: "cursor")) == nil)
        #expect(AgentTaskControl.cliTool(process(601, name: "cursor-agent")) == .cursor)
    }
    @Test func acceptsNativeInstallerVersionedExecutable() {
        let native = "/Users/test/.local/share/claude/versions/2.1.299"
        #expect(AgentTaskControl.cliTool(process(700, name: "2.1.299", path: native)) == .claude)
        #expect(AgentTaskControl.cliTool(process(701, name: "2.1.299", path: "/Users/test/.local/share/claude/2.1.299")) == nil)
        #expect(AgentTaskControl.cliTool(process(702, name: "2.1.299", path: native, hint: "codex")) == nil)
        #expect(AgentTaskControl.cliTool(process(703, name: "2.1.299", path: "/Applications/Claude.app/Contents/claude/versions/2.1.299")) == nil)
        let tasks = AgentTaskFixture([process(710, name: "2.1.299", path: native), process(711, parent: 710, name: "node")]).discover()
        #expect(tasks.map(\.tool) == [.claude])
        #expect(tasks.first?.members.map(\.pid) == [710, 711])
    }
    @Test func excludesHostFamilyOwnAncestorsDescendantsAndProtectedMembers() {
        let host = process(100, name: "Codex", path: "/Applications/Codex.app/Contents/MacOS/Codex")
        let rows = [host, process(200, parent: 100), process(300), process(301, parent: 300, name: "tmux"), process(400), process(999, parent: 400, name: "DonyHome"), process(500, parent: 999)]
        let tasks = AgentTaskFixture(rows).discover()
        #expect(tasks.isEmpty)
        let otherUID = AgentTaskFixture([process(600), process(601, parent: 600, name: "node", uid: 0)])
        #expect(otherUID.discover().isEmpty)
        let noStart = AgentTaskFixture([process(0), process(-1), process(700, start: 0)])
        #expect(noStart.discover().isEmpty)
    }
    @Test func requiresKnownWorkingDirectoryForEveryMember() {
        let fixture = AgentTaskFixture([process(200), process(201, parent: 200, name: "node")])
        fixture.unknownCWD.insert(201)
        #expect(fixture.discover().isEmpty)
    }
    @Test func revalidatesPIDStartAndWholeFamilyBeforeAnySignal() throws {
        let fixture = AgentTaskFixture([process(200)])
        let task = try #require(fixture.discover().first)
        let control = fixture.control()
        fixture.rows = [process(200, start: 101)]
        #expect(throws: AgentTaskError.self) { try control.pause(task) }
        #expect(fixture.signals.isEmpty)
        fixture.rows = [process(200), process(201, parent: 200, name: "Terminal")]
        #expect(throws: AgentTaskError.self) { try control.pause(task) }
        #expect(fixture.signals.isEmpty)
    }
    @Test func rootStopsFirstAndPartialPauseRollsBackOwnedMembers() throws {
        let fixture = AgentTaskFixture([process(200), process(201, parent: 200, name: "node")])
        let task = try #require(fixture.discover().first)
        fixture.failSignal = { pid, signal in pid == 201 && signal == SIGSTOP }
        let control = fixture.control()
        #expect(throws: AgentTaskError.self) { try control.pause(task) }
        #expect(fixture.signals.map { $0.0 } == [200, 201, 200])
        #expect(fixture.signals.map { $0.1 } == [SIGSTOP, SIGSTOP, SIGCONT])
        #expect(control.ownedTasks.isEmpty)
        #expect(fixture.saved.isEmpty)
    }
    @Test func retainsFailedRollbackForManualRecovery() throws {
        let fixture = AgentTaskFixture([process(200), process(201, parent: 200, name: "node")])
        let task = try #require(fixture.discover().first)
        fixture.failSignal = { pid, signal in (pid == 201 && signal == SIGSTOP) || (pid == 200 && signal == SIGCONT) }
        let control = fixture.control()
        #expect(throws: AgentTaskError.self) { try control.pause(task) }
        #expect(control.ownedTasks.first?.members.map(\.pid) == [200])
        #expect(fixture.saved.first?.members.map(\.pid) == [200])
    }
    @Test func neverTakesOwnershipOfExternallyStoppedProcesses() throws {
        let fixture = AgentTaskFixture([process(200)])
        fixture.stopped.insert(200)
        let task = try #require(fixture.discover().first)
        let control = fixture.control()
        #expect(throws: AgentTaskError.self) { try control.pause(task) }
        #expect(throws: AgentTaskError.self) { try control.resume(id: task.id) }
        #expect(fixture.signals.isEmpty)
    }
    @Test func persistsExactOwnershipAndRecoversOnlyMatchingIdentities() throws {
        let fixture = AgentTaskFixture([process(200), process(201, parent: 200, name: "node")])
        let task = try #require(fixture.discover().first)
        try fixture.control().pause(task)
        let encoded = try JSONEncoder().encode(fixture.saved)
        let recovered = try JSONDecoder().decode([OwnedAgentTask].self, from: encoded)
        fixture.signals = []
        fixture.rows = [process(200, start: 101), process(201, parent: 1, name: "node", start: 102)]
        let control = fixture.control(owned: recovered)
        let count = try control.resume(id: task.id)
        #expect(count == 0)
        #expect(fixture.signals.isEmpty)
        #expect(control.ownedTasks.isEmpty)
    }
    @Test func doesNotResumeIfAnyOwnedMemberBecomesProtected() throws {
        let fixture = AgentTaskFixture([process(200), process(201, parent: 200, name: "node")])
        let task = try #require(fixture.discover().first)
        let control = fixture.control()
        try control.pause(task)
        fixture.signals = []
        fixture.rows = [process(200), process(201, parent: 200, name: "node", path: "/Applications/ChatGPT.app/Contents/MacOS/node")]
        #expect(throws: AgentTaskError.self) { try control.resume(id: task.id) }
        #expect(fixture.signals.isEmpty)
    }
    @Test func resumesOwnedChildrenBeforeRootAndPausedStopRequestsTERMThenCONT() throws {
        let fixture = AgentTaskFixture([process(200), process(201, parent: 200, name: "node")])
        let task = try #require(fixture.discover().first)
        let control = fixture.control()
        try control.pause(task)
        fixture.signals = []
        let resumed = try control.resume(id: task.id)
        #expect(resumed == 2)
        #expect(fixture.signals.map { $0.0 } == [201, 200])
        #expect(fixture.signals.allSatisfy { $0.1 == SIGCONT })
        try control.pause(task)
        fixture.signals = []
        let terminated = try control.stop(task)
        #expect(terminated == 2)
        #expect(fixture.signals.map { $0.0 } == [201, 201, 200, 200])
        #expect(fixture.signals.map { $0.1 } == [SIGTERM, SIGCONT, SIGTERM, SIGCONT])
        #expect(control.ownedTasks.isEmpty)
    }
    @Test func revalidatesAgainWhenWorkerChangesDuringPause() throws {
        let fixture = AgentTaskFixture([process(200), process(201, parent: 200, name: "node")])
        let task = try #require(fixture.discover().first)
        fixture.afterSignal = { pid, signal in
            if pid == 200 && signal == SIGSTOP { fixture.rows[1] = self.process(201, parent: 200, name: "node", start: 101) }
        }
        let control = fixture.control()
        #expect(throws: AgentTaskError.self) { try control.pause(task) }
        #expect(fixture.signals.map { $0.0 } == [200, 200])
        #expect(fixture.signals.map { $0.1 } == [SIGSTOP, SIGCONT])
        #expect(control.ownedTasks.isEmpty)
    }
    @Test func canonicalHostWorkspaceOverlapRejectsIndependentCLIAndItsAncestor() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("AgentTaskWorkspace-" + UUID().uuidString)
        let workspace = base.appendingPathComponent("active/project")
        let independent = base.appendingPathComponent("independent/project")
        let alias = base.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: independent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: workspace)
        defer { try? FileManager.default.removeItem(at: base) }
        let host = process(100, name: "Codex", path: "/Applications/Codex.app/Contents/MacOS/Codex")
        let fixture = AgentTaskFixture([host, process(101, parent: 100, name: "node"), process(200), process(300)])
        fixture.directories = [100: "/", 101: workspace.path, 200: alias.path, 300: independent.path]
        #expect(fixture.discover().map(\.root.pid) == [300])
        fixture.directories[200] = base.appendingPathComponent("active").path
        #expect(fixture.discover().map(\.root.pid) == [300])
    }
    @Test func ignoresBroadHostHomeDocumentsAndRootDirectories() throws {
        let host = process(100, name: "Codex", path: "/Applications/Codex.app/Contents/MacOS/Codex")
        let fixture = AgentTaskFixture([host, process(101, parent: 100, name: "node"), process(200)])
        fixture.directories = [100: "/", 101: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents").path]
        #expect(fixture.discover().map(\.root.pid) == [200])
    }
    @Test func rejectsOwnCurrentWorkingDirectoryOverlap() throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("AgentOwnWorkspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let fixture = AgentTaskFixture([process(999, name: "DonyHome"), process(200)])
        fixture.directories = [999: workspace.path, 200: workspace.path]
        #expect(fixture.discover().isEmpty)
    }
    @Test func checksNewHostWorkspaceBeforePauseButAllowsOwnedRecovery() throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("AgentRecoveryWorkspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let fixture = AgentTaskFixture([process(200)])
        fixture.directories = [200: workspace.path]
        let task = try #require(fixture.discover().first)
        let control = fixture.control()
        let host = process(100, name: "Codex", path: "/Applications/Codex.app/Contents/MacOS/Codex")
        fixture.rows.append(host); fixture.directories[100] = workspace.path
        #expect(throws: AgentTaskError.self) { try control.pause(task) }
        #expect(fixture.signals.isEmpty)
        fixture.rows = [process(200)]
        try control.pause(task)
        fixture.signals = []
        fixture.rows.append(host)
        let resumed = try control.resume(id: task.id)
        #expect(resumed == 1)
        #expect(fixture.signals.map { $0.0 } == [200])
        #expect(fixture.signals.map { $0.1 } == [SIGCONT])
        #expect(control.ownedTasks.isEmpty)
        #expect(fixture.saved.isEmpty)
    }

    @Test func ownedRecoveryDoesNotRequireAStillReadableWorkingDirectory() throws {
        let fixture = AgentTaskFixture([process(200), process(201, parent: 200, name: "node")])
        let task = try #require(fixture.discover().first)
        let control = fixture.control()
        try control.pause(task)
        fixture.signals = []
        fixture.unknownCWD = [200, 201]
        let resumed = try control.resume(id: task.id)
        #expect(resumed == 2)
        #expect(fixture.signals.map { $0.0 } == [201, 200])
        #expect(fixture.signals.allSatisfy { $0.1 == SIGCONT })
        #expect(control.ownedTasks.isEmpty)
    }

}
