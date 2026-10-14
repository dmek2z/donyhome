import Testing
@testable import DonyCore

@Suite struct DevelopmentResourceTests {
    func process(_ name: String, _ path: String) -> ProcessReading {
        ProcessReading(pid: 300, uid: 501, startSeconds: 1, startMicroseconds: 0, name: name, path: path, memoryBytes: 123, cpuNanos: nil, cpuPercent: nil)
    }
    @Test func localizedToolNamesMatchRealEditorAndTerminalIdentities() {
        #expect(DevelopmentResourceFilter.includes(process("Code", "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"), tool: .vscode))
        #expect(DevelopmentResourceFilter.includes(process("iTerm2", "/Applications/iTerm.app/Contents/MacOS/iTerm2"), tool: .terminal))
        #expect(!DevelopmentResourceFilter.includes(process("Code", "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"), tool: .claude))
    }
    @Test func registeredIdentityOverridesDisplayNameAndAllowsClearingFilter() {
        let row = process("Custom Editor", "/Applications/Custom Editor.app/Contents/MacOS/helper")
        #expect(DevelopmentResourceFilter.includes(row, tool: .windsurf, applicationTools: ["/Applications/Custom Editor.app": .windsurf]))
        #expect(DevelopmentResourceFilter.includes(row, tool: nil))
    }
    @Test func sharedCopilotEditorResourcesRemainReviewable() {
        #expect(DevelopmentResourceFilter.includes(process("Code", "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"), tool: .copilot))
    }
}
