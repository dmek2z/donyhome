import Foundation

public enum DevelopmentResourceFilter {
    public static func includes(_ process: ProcessReading, tool: AITool?, applicationTools: [String: AITool] = [:]) -> Bool {
        guard let tool else { return true }
        let actual = AITool.identify(process, applicationTools: applicationTools)
        return actual == tool || (tool == .copilot && actual == .vscode)
    }
}
