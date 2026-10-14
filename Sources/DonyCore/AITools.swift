import Foundation

public enum AITool: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatGPT, codex, claude, hermes, orca, cursor, herdr, cmux, tmux, terminal, opencode, gemini, aider, copilot, vscode, windsurf, other
    public var id: String { rawValue }
    /// ChatGPT 앱과 Codex는 같은 OpenAI 도구라 하나로 다룬다. `chatGPT` 값은 저장된 설정을 읽기 위해서만 남긴다.
    public var canonical: AITool { self == .chatGPT ? .codex : self }
    public static var selectable: [AITool] { allCases.filter { $0 != .chatGPT } }
    public var title: String {
        switch self {
        case .chatGPT: return "ChatGPT"; case .codex: return "Codex"; case .claude: return "Claude"; case .hermes: return "Hermes"; case .orca: return "Orca"; case .cursor: return "Cursor"
        case .herdr: return "Herdr"; case .cmux: return "cmux"; case .tmux: return "tmux"; case .terminal: return "터미널"; case .opencode: return "OpenCode"; case .gemini: return "Gemini"; case .aider: return "Aider"; case .copilot: return "Copilot"; case .vscode: return "VS Code"; case .windsurf: return "Windsurf"; case .other: return "기타 개발 도구"
        }
    }
    public var executableNames: [String] {
        switch self {
        case .chatGPT: return []; case .codex: return ["codex", "ChatGPT"]; case .cursor: return ["cursor", "cursor-agent"]; case .claude: return ["claude", "claude-code"]
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
    /// 네이티브 설치는 `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.0`처럼
    /// 버전 이름의 실행 파일을 실행해서 프로세스 이름도 버전이 된다. `<도구>/versions/<버전>`에서 도구 이름(소문자)을 꺼낸다.
    public static func versionedInstallName(_ path: String) -> String? {
        let components = path.lowercased().split(separator: "/")
        guard components.count >= 3, components[components.count - 2] == "versions" else { return nil }
        return String(components[components.count - 3])
    }
    /// 도구별 별칭(소문자)을 한 번만 계산한다.
    private static let aliasTable: [(tool: AITool, aliases: Set<String>)] = allCases.map { tool in
        (tool, Set([tool.title.lowercased()] + tool.executableNames.map { $0.lowercased() }))
    }
    /// 경로의 `○○.app` 구성요소 이름들(소문자). 경로 전체를 도구마다 다시 검색하지 않는다.
    private static func appNames(in lowercasedPath: String) -> Set<String> {
        var names = Set<String>()
        for component in lowercasedPath.split(separator: "/") where component.hasSuffix(".app") { names.insert(String(component.dropLast(4))) }
        return names
    }
    private static func applicationPrefixes(_ applicationTools: [String: AITool]) -> [(prefix: String, key: String)] {
        applicationTools.keys.sorted { $0.count > $1.count }.map { ($0 + "/", $0) }
    }
    public static func identify(_ process: ProcessReading, applicationTools: [String: AITool] = [:]) -> Self? {
        rawIdentify(process, applicationTools: applicationTools, prefixes: applicationPrefixes(applicationTools))?.canonical
    }
    private static func rawIdentify(_ process: ProcessReading, applicationTools: [String: AITool], prefixes: [(prefix: String, key: String)]) -> Self? {
        if let hint = process.toolHint.flatMap(Self.init(rawValue:)) { return hint }
        if let match = prefixes.first(where: { process.path.hasPrefix($0.prefix) }) { return applicationTools[match.key] }
        let apps = appNames(in: process.path.lowercased()); let name = process.name.lowercased()
        let versioned = versionedInstallName(process.path)
        return aliasTable.first { entry in
            !entry.aliases.isDisjoint(with: apps) || entry.aliases.contains(name) || versioned.map(entry.aliases.contains) == true || (entry.tool == .tmux && name.hasPrefix("tmux:")) || (entry.tool == .herdr && name == "herdr-server")
        }?.tool
    }
    public static func assignments(_ processes: [ProcessReading], currentUID: UInt32, applicationTools: [String: AITool] = [:]) -> [Int32: AITool] {
        let local = processes.filter { $0.uid == currentUID }
        let byPID = Dictionary(local.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let prefixes = applicationPrefixes(applicationTools)
        // 같은 이름·경로의 헬퍼 프로세스가 많아서 판별 결과를 재사용한다.
        var memo: [String: Self?] = [:]
        var direct: [Int32: AITool] = [:]
        for process in local {
            let key = process.name + "\u{0}" + process.path + "\u{0}" + (process.toolHint ?? "")
            let tool: Self?
            if let cached = memo[key] { tool = cached }
            else { tool = rawIdentify(process, applicationTools: applicationTools, prefixes: prefixes)?.canonical; memo[key] = .some(tool) }
            if let tool, direct[process.pid] == nil { direct[process.pid] = tool }
        }
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
        var grouped: [AITool: [ProcessReading]] = [:]
        for process in processes where process.uid == currentUID { if let tool = owners[process.pid] { grouped[tool, default: []].append(process) } }
        return allCases.compactMap { tool in grouped[tool].map { AIToolUsage(tool: tool, processes: $0) } }.sorted { $0.bytes > $1.bytes }
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

public enum CharacterActivity: String, CaseIterable, Sendable {
    case relaxed, working, overloaded
    public static func resolve(cpu: Double?, pressure: MemoryPressure) -> Self {
        if pressure == .critical || (cpu ?? 0) >= 85 { return .overloaded }
        if pressure == .warning || (cpu ?? 0) >= 50 { return .working }
        return .relaxed
    }
    public var interval: Double { switch self { case .relaxed: 0.65; case .working: 0.22; case .overloaded: 0.10 } }
}
