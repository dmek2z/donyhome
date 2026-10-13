import Testing
import Foundation
@testable import DonyCore

@Suite struct AIToolTests {
    func process(_ name: String, path: String, memory: Int64 = 100, uid: UInt32 = 501, pid: Int32 = 100) -> ProcessReading {
        ProcessReading(pid: pid, uid: uid, startSeconds: 1, startMicroseconds: 0, name: name, path: path, memoryBytes: memory, cpuNanos: nil, cpuPercent: nil)
    }
    @Test func attributesHelpersAndCLIsWithoutMatchingUnrelatedNames() {
        #expect(AITool.identify(process("Cursor Helper", path: "/Applications/Cursor.app/Contents/Frameworks/helper")) == .cursor)
        #expect(AITool.identify(process("claude", path: "/Users/test/.local/bin/claude")) == .claude)
        #expect(AITool.identify(process("codex", path: "/usr/local/bin/codex")) == .codex)
        #expect(AITool.identify(process("hermes", path: "/usr/local/bin/hermes")) == .hermes)
        #expect(AITool.identify(process("Orca", path: "/Applications/Orca.app/Contents/MacOS/Orca")) == .orca)
        #expect(AITool.identify(process("ChatGPT", path: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT")) == .chatGPT)
        #expect(AITool.identify(process("cursor-helper-unrelated", path: "/tmp/cursor-helper-unrelated")) == nil)
        #expect(AITool.identify(process("node", path: "/usr/local/bin/node")) == nil)
    }
    @Test func totalsOnlyCurrentUsersMeasuredAIProcesses() {
        let processes = [process("Cursor", path: "/Applications/Cursor.app/Contents/MacOS/Cursor", memory: 200),
                         process("Cursor Helper", path: "/Applications/Cursor.app/Contents/Frameworks/helper", memory: 300, pid: 101),
                         process("claude", path: "/usr/bin/claude", memory: 500, uid: 0, pid: 102),
                         process("node", path: "/usr/bin/node", memory: 900, pid: 103),
                         process("hermes", path: "/usr/bin/hermes", memory: -1, pid: 104)]
        let usage = AITool.usage(processes, currentUID: 501)
        #expect(usage.first { $0.tool == .cursor }?.bytes == 500)
        #expect(usage.first { $0.tool == .cursor }?.processes.count == 2)
        #expect(!usage.contains { $0.tool == .claude })
        #expect(usage.first { $0.tool == .hermes }?.bytes == 0)
    }
    @Test func registeredBundleIdentityOverridesAnOutdatedDisplayName() {
        let app = process("ChatGPT", path: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT")
        let helper = process("Codex (Renderer)", path: "/Applications/ChatGPT.app/Contents/Frameworks/helper", pid: 101)
        let usage = AITool.usage([app, helper], currentUID: 501, applicationTools: ["/Applications/ChatGPT.app": .codex])
        #expect(usage.count == 1)
        #expect(usage.first?.tool == .codex)
        #expect(usage.first?.bytes == 200)
    }
}
