import Foundation

public enum AITool: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatGPT, codex, claude, hermes, orca, cursor, herdr, cmux, tmux, terminal, opencode, gemini, aider, copilot, vscode, windsurf, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .chatGPT: return "ChatGPT"; case .codex: return "Codex"; case .claude: return "Claude"; case .hermes: return "Hermes"; case .orca: return "Orca"; case .cursor: return "Cursor"
        case .herdr: return "Herdr"; case .cmux: return "cmux"; case .tmux: return "tmux"; case .terminal: return "터미널"; case .opencode: return "OpenCode"; case .gemini: return "Gemini"; case .aider: return "Aider"; case .copilot: return "Copilot"; case .vscode: return "VS Code"; case .windsurf: return "Windsurf"; case .other: return "기타 개발 도구"
        }
    }
    public var executableNames: [String] {
        switch self {
        case .chatGPT: return []; case .cursor: return ["cursor", "cursor-agent"]; case .claude: return ["claude", "claude-code"]
        case .terminal: return ["Terminal", "iTerm", "iTerm2", "Warp", "Ghostty", "WezTerm", "Alacritty", "kitty"]
        case .vscode: return ["code", "Code", "Visual Studio Code"]; case .other: return []
        default: return [rawValue]
        }
    }
    public static func isInterpreter(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["node", "bun", "python", "python3", "ruby", "php", "java", "dotnet", "zsh", "bash", "sh", "env"].contains(lower) || lower.hasPrefix("python3.")
    }
    public static func commandHint(_ arguments: [String]) -> Self? {
        guard let executable = arguments.first else { return nil }
        let name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        if let direct = allCases.first(where: { $0 != .terminal && $0.executableNames.map { $0.lowercased() }.contains(name) }) { return direct }
        guard isInterpreter(name), arguments.count > 1, !arguments[1].hasPrefix("-") else { return nil }
        let script = arguments[1].lowercased()
        let scriptName = URL(fileURLWithPath: script).lastPathComponent
        if script.contains("/node_modules/@anthropic-ai/claude-code/") { return .claude }
        if script.contains("/node_modules/@openai/codex/") { return .codex }
        if script.contains("/node_modules/@google/gemini-cli/") { return .gemini }
        return allCases.first { tool in tool != .terminal && tool != .other && tool.executableNames.map { $0.lowercased() }.contains(scriptName) }
    }
    public static func identify(_ process: ProcessReading, applicationTools: [String: AITool] = [:]) -> Self? {
        if let hint = process.toolHint.flatMap(Self.init(rawValue:)) { return hint }
        if let application = applicationTools.keys.sorted(by: { $0.count > $1.count }).first(where: { process.path.hasPrefix($0 + "/") }) { return applicationTools[application] }
        let path = process.path.lowercased(); let name = process.name.lowercased()
        return allCases.first { tool in
            let aliases = [tool.title.lowercased()] + tool.executableNames.map { $0.lowercased() }
            return aliases.contains { path.contains("/" + $0 + ".app/") || name == $0 } || (tool == .tmux && name.hasPrefix("tmux:")) || (tool == .herdr && name == "herdr-server")
        }
    }
    public static func assignments(_ processes: [ProcessReading], currentUID: UInt32, applicationTools: [String: AITool] = [:]) -> [Int32: AITool] {
        let local = processes.filter { $0.uid == currentUID }
        let byPID = Dictionary(local.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let direct = Dictionary(local.compactMap { process in identify(process, applicationTools: applicationTools).map { (process.pid, $0) } }, uniquingKeysWith: { first, _ in first })
        var result: [Int32: AITool] = [:]
        for process in local {
            var current = process.pid; var seen = Set<Int32>()
            while seen.count < 64, seen.insert(current).inserted, let row = byPID[current] {
                if let tool = direct[current] { result[process.pid] = tool; break }
                current = row.parentPID
            }
            if result[process.pid] == nil && isInterpreter(process.name) { result[process.pid] = .other }
        }
        return result
    }
    public static func usage(_ processes: [ProcessReading], currentUID: UInt32, applicationTools: [String: AITool] = [:]) -> [AIToolUsage] {
        let owners = assignments(processes, currentUID: currentUID, applicationTools: applicationTools)
        return allCases.compactMap { tool in
            let family = processes.filter { $0.uid == currentUID && owners[$0.pid] == tool }
            return family.isEmpty ? nil : AIToolUsage(tool: tool, processes: family)
        }.sorted { $0.bytes > $1.bytes }
    }
}
public struct AIToolUsage: Identifiable, Sendable {
    public var id: String { tool.id }
    public let tool: AITool
    public let processes: [ProcessReading]
    public var bytes: Int64 { processes.reduce(0) { $0 + max(0, $1.memoryBytes) } }
}
public enum CharacterMode: String, Codable, CaseIterable { case color, monochrome
    public var title: String { self == .color ? "컬러" : "흑백" }
}
