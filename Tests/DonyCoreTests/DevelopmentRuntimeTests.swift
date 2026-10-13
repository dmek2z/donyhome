import Foundation
import Testing
@testable import DonyCore

@Suite struct DevelopmentRuntimeTests {
    func process(_ pid: Int32, _ parent: Int32, _ name: String, uid: UInt32 = 501, hint: String? = nil) -> ProcessReading {
        ProcessReading(pid: pid, uid: uid, startSeconds: 1, startMicroseconds: 0, name: name, path: "/usr/local/bin/" + name, memoryBytes: 100, cpuNanos: nil, cpuPercent: nil, parentPID: parent, toolHint: hint)
    }
    @Test func multipleAgentsInsideMultiplexersOwnTheirWorkersWithoutDoubleCounting() {
        let rows = [process(10, 1, "herdr"), process(11, 10, "zsh"), process(12, 11, "claude"), process(13, 12, "node"), process(14, 11, "codex"), process(15, 14, "python3"), process(16, 10, "tmux"), process(17, 16, "hermes"), process(18, 17, "python3")]
        let usage = AITool.usage(rows, currentUID: 501)
        #expect(usage.first { $0.tool == .claude }?.bytes == 200)
        #expect(usage.first { $0.tool == .codex }?.bytes == 200)
        #expect(usage.first { $0.tool == .hermes }?.bytes == 200)
        #expect(usage.reduce(0) { $0 + $1.processes.count } == rows.count)
        #expect(usage.reduce(Int64(0)) { $0 + $1.bytes } == 900)
    }
    @Test func shellWrappersAndForeignUIDParentsCannotMisattributeAWorker() {
        let wrapped = process(30, 1, "node", hint: "claude")
        let child = process(31, 30, "node")
        let foreign = process(40, 1, "codex", uid: 0)
        let unrelated = process(41, 40, "python3")
        let usage = AITool.usage([wrapped, child, foreign, unrelated], currentUID: 501)
        #expect(usage.first { $0.tool == .claude }?.bytes == 200)
        #expect(!usage.contains { $0.tool == .codex })
        #expect(usage.first { $0.tool == .other }?.bytes == 100)
    }
    @Test func argumentsRecognizeProgramPathsButNeverPromptsOrEnvironmentSecrets() {
        #expect(AITool.commandHint(["node", "/opt/node_modules/@anthropic-ai/claude-code/cli.js", "--api-key", "secret"]) == .claude)
        #expect(AITool.commandHint(["python3", "/home/me/.local/bin/hermes", "--prompt", "codex"]) == .hermes)
        #expect(AITool.commandHint(["node", "--eval", "console.log('claude')"]) == nil)
        #expect(AITool.commandHint(["zsh", "-c", "echo codex"]) == nil)
    }
    @Test func graphCyclesRemainBounded() {
        let rows = [process(20, 21, "node"), process(21, 20, "python3")]
        #expect(AITool.usage(rows, currentUID: 501).reduce(0) { $0 + $1.processes.count } == 2)
    }
    @Test func malformedRuntimeOutputIsDistinctFromValidEmptyDiscovery() {
        #expect(DevelopmentRuntime.metadataPaths("{\"workspaces\":[", tool: .herdr) == nil)
        #expect(DevelopmentRuntime.metadataPaths("{\"result\":{\"worktrees\":[]}}", tool: .orca) == [])
        #expect(DevelopmentRuntime.metadataPaths("connection error", tool: .tmux) == nil)
        #expect(DevelopmentRuntime.metadataPaths("", tool: .tmux) == [])
        #expect(DevelopmentRuntime.metadataPaths(#"{"error":"not connected"}"#, tool: .herdr) == nil)
        #expect(DevelopmentRuntime.metadataPaths(#"{"unrelated":42}"#, tool: .orca) == nil)
    }
    @Test func runtimeMetadataCollectsOnlyLocalWorkspacePaths() throws {
        let data = Data(#"{"result":{"workspaces":[{"cwd":"/Users/test/project"},{"cwd":"/remote/project","machine":"remote"}],"panes":[{"foreground_cwd":"/Users/test/second"}],"prompt":"/tmp/never-use"}}"#.utf8)
        #expect(Set(DevelopmentRuntime.paths(in: data)) == ["/Users/test/project", "/Users/test/second"])
        #expect(DevelopmentRuntime.tmuxPaths("42\t/Users/test/project\n43\t/Users/test/second\n") == ["/Users/test/project", "/Users/test/second"])
    }
    @Test func folderLinkingSupportsMultipleToolsWithoutDuplicatingSameLink() {
        let existing = [LinkedProject(tool: .claude, path: "/project")]
        let linked = DevelopmentRuntime.link(projectPaths: ["/project"], tools: [.claude, .codex, .herdr], existing: existing)
        #expect(linked.count == 3)
        #expect(Set(linked.map(\.tool)) == [.claude, .codex, .herdr])
    }
    @Test func orcaWorktreePathsExcludeRemoteHostsAndPromptPaths() {
        let data = Data(#"{"result":{"worktrees":[{"worktreeId":"1","path":"/Users/test/local","hostId":"local","terminalPlatform":"darwin"},{"worktreeId":"2","path":"/Users/test/remote","hostId":"ssh:server"},{"worktreeId":"3","path":"/Users/test/linux","terminalPlatform":"linux"}],"path":"/tmp/prompt"}}"#.utf8)
        #expect(DevelopmentRuntime.paths(in: data) == ["/Users/test/local"])
    }
    @Test func terminalSubdirectoriesResolveToTheNearestProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src/components"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("package.json"))
        #expect(DevelopmentRuntime.projectRoot(forWorkingDirectory: root.appendingPathComponent("src/components").path)?.lastPathComponent == root.lastPathComponent)
        #expect(DevelopmentRuntime.projectRoot(forWorkingDirectory: "/") == nil)
    }
}
