import Foundation

public enum AITool: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatGPT, codex, claude, hermes, orca, cursor
    public var id: String { rawValue }
    public var title: String {
        switch self { case .chatGPT: return "ChatGPT"; case .codex: return "Codex"; case .claude: return "Claude"; case .hermes: return "Hermes"; case .orca: return "Orca"; case .cursor: return "Cursor" }
    }
    public static func identify(_ process: ProcessReading, applicationTools: [String: AITool] = [:]) -> Self? {
        if let application = applicationTools.keys.sorted(by: { $0.count > $1.count }).first(where: { process.path.hasPrefix($0 + "/") }) { return applicationTools[application] }
        let path = process.path.lowercased()
        let name = process.name.lowercased()
        return allCases.first { tool in
            let stem = tool.title.lowercased()
            return path.contains("/" + stem + ".app/") || name == stem || (tool == .claude && name == "claude-code")
        }
    }
    public static func usage(_ processes: [ProcessReading], currentUID: UInt32, applicationTools: [String: AITool] = [:]) -> [AIToolUsage] {
        allCases.compactMap { tool in
            let family = processes.filter { $0.uid == currentUID && identify($0, applicationTools: applicationTools) == tool }
            guard !family.isEmpty else { return nil }
            return AIToolUsage(tool: tool, processes: family)
        }.sorted { $0.bytes > $1.bytes }
    }
}
public struct AIToolUsage: Identifiable, Sendable {
    public var id: String { tool.id }
    public let tool: AITool
    public let processes: [ProcessReading]
    public var bytes: Int64 { processes.reduce(0) { $0 + max(0, $1.memoryBytes) } }
}
