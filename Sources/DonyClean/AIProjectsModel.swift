import Foundation
import AppKit
import DonyCore

extension AppModel {
    var aiApplicationTools: [String: AITool] {
        var mapping: [String: AITool] = [:]
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            guard let path = app.bundleURL?.path else { continue }
            if app.bundleIdentifier == "com.openai.codex" { mapping[path] = .codex }
            else if app.bundleIdentifier == "com.openai.chat" { mapping[path] = .chatGPT }
            else if let tool = AITool.allCases.first(where: { $0.title.lowercased() == app.localizedName?.lowercased() }) { mapping[path] = tool }
        }
        return mapping
    }
    var aiUsage: [AIToolUsage] { AITool.usage(snapshot.processes, currentUID: getuid(), applicationTools: aiApplicationTools) }
    var selectedProjects: [LinkedProject] { linkedProjects.filter { $0.enabled && (projectSource == "모두" || $0.discovered == (projectSource == "작업 이력")) } }
    func connectInstalledTools() {
        connectedTools.formUnion(Set(AITool.allCases.filter { DevelopmentRuntime.installed($0) }).union(aiUsage.map(\.tool)))
        saveConnectedTools(); discoverProjects(includeInventory: false)
    }
    func saveProjectSettings() {
        projectRetentionDays = max(1, min(3650, projectRetentionDays))
        UserDefaults.standard.set(projectRetentionDays, forKey: "projectRetentionDays")
        UserDefaults.standard.set(projectCleanupScope.rawValue, forKey: "projectCleanupScope")
        UserDefaults.standard.set(projectRequireRemoteBackup, forKey: "projectRequireRemoteBackup")
        UserDefaults.standard.set(projectSource, forKey: "projectSource")
        if let data = try? JSONEncoder().encode(linkedProjects) { UserDefaults.standard.set(data, forKey: "linkedProjects") }
        projectScan = ScanResult(); projectScanDate = nil
    }
    func addProject(tool: AITool) { addProjects(tools: [tool]) }
    func addProjects(tools: Set<AITool>) {
        guard !busy, !tools.isEmpty else { return }
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = true
        picker.prompt = "프로젝트 연결"; picker.message = "프로젝트 폴더 선택"
        guard picker.runModal() == .OK else { return }
        for url in picker.urls {
            do {
                let root = try ProjectCleanup.projectRoot(url.path)
                linkedProjects = DevelopmentRuntime.link(projectPaths: [root.path], tools: tools, existing: linkedProjects)
            } catch { banner = "프로젝트 표시 파일이 없거나 보호된 경로입니다: " + url.path }
        }
        saveProjectSettings()
    }
    func discoverProjects(includeInventory: Bool = true) {
        guard let (token, epoch) = begin(includeInventory ? "프로젝트 파일 검사" : "개발 도구 연동 확인") else { return }
        let report = progress(epoch)
        Task {
            let selectedTools = connectedTools
            let processes = snapshot.processes; let applicationTools = aiApplicationTools
            let linkedProjectsSnapshot = linkedProjects
            let result = await Task.detached(priority: .utility) {
                let history = ProjectDiscovery.discover(token: token, tools: selectedTools)
                var runtime = DevelopmentRuntime.discover(tools: selectedTools, token: token)
                runtime.projects += DevelopmentRuntime.runningProjects(processes: processes, currentUID: getuid(), applicationTools: applicationTools, tools: selectedTools)
                let worktrees = ProjectInventory.discoverManagedWorktrees(token: token).filter { selectedTools.contains($0.tool) }
                let inventory = includeInventory ? ProjectInventory.inspectIsolated(projects: history.projects + runtime.projects + worktrees + linkedProjectsSnapshot, executable: Bundle.main.executableURL!, token: token, progress: report) : []
                return (history, runtime, worktrees, inventory)
            }.value
            mergeDiscoveredProjects(result.0.projects + result.1.projects + result.2)
            if includeInventory { projectInventory = result.3 }; connectionCheckedAt = Date(); connectionIssues = result.0.issues + result.3.flatMap(\.issues)
            for tool in selectedTools {
                let count = Set((result.0.projects + result.1.projects + result.2).filter { $0.tool == tool }.map(\.path)).count
                let status: String
                if let runtime = result.1.statuses[tool] { status = runtime + " · \(count)개 프로젝트" }
                else if tool == .chatGPT { status = "폴더 연결만 · 클라우드 대화 미지원" }
                else if [.codex, .claude, .cursor].contains(tool) { status = count > 0 ? "로컬 작업 이력 · \(count)개 프로젝트" : "읽을 수 있는 로컬 이력 없음" }
                else { status = count > 0 ? "실행 경로 · \(count)개 프로젝트" : "폴더 연결 필요" }
                toolStatuses[tool] = status
            }
            projectSummary = "\(Set((result.0.projects + result.1.projects + result.2).map(\.path)).count)개 프로젝트 발견 · 자동 정리할 폴더를 선택해 주세요."
            finish(token.isCancelled, issues: connectionIssues)
        }
    }
    func mergeDiscoveredProjects(_ projects: [LinkedProject]) {
        for project in projects {
            if let index = linkedProjects.firstIndex(where: { $0.id == project.id && $0.discovered }) {
                linkedProjects[index].lastActivity = project.lastActivity
            } else { linkedProjects.append(project) }
        }
        if let data = try? JSONEncoder().encode(linkedProjects) { UserDefaults.standard.set(data, forKey: "linkedProjects") }
    }
    func scanAIProjects() {
        guard let (token, epoch) = begin("AI 프로젝트 보관 기간 검사") else { return }
        let selected = selectedProjects; let allLinks = linkedProjects; let days = projectRetentionDays; let scope = projectCleanupScope; let requireRemote = projectRequireRemoteBackup
        let processes = snapshot.processes; let tools = Set(aiUsage.map(\.tool)); let report = progress(epoch)
        let retained = duplicateOriginals.values.map { $0.url.path } + similarOriginals.map { $0.url.path } + [Bundle.main.bundleURL.path]
        Task {
            let output = await Task.detached(priority: .utility) {
                // Refresh activity even for manually linked folders before classifying them as stale.
                let discovery = ProjectDiscovery.discover(token: token)
                var links = selected
                for index in links.indices {
                    let dates = discovery.projects.filter { $0.path == links[index].path }.compactMap(\.lastActivity)
                    links[index].lastActivity = ([links[index].lastActivity].compactMap { $0 } + dates).max()
                }
                var active = ProjectDiscovery.activePaths(processes: processes, currentUID: getuid()) + retained
                for project in links {
                    if (allLinks + discovery.projects).contains(where: { $0.path == project.path && tools.contains($0.tool) }) { active.append(project.path) }
                }
                var result = ProjectCleanup.scan(projects: links, days: days, scope: scope, activePaths: active, runningTools: tools, token: token, progress: report)
                if scope == .wholeProject {
                    result = ProjectBackupPolicy.filter(result, token: token) { item in
                        let structure = GitBackup.structuralCheck(root: item.url)
                        guard structure.verified else { return structure }
                        return requireRemote ? GitBackup.check(root: item.url) : structure
                    }
                }
                result.cancelled = result.cancelled || token.isCancelled
                if result.cancelled { result.items.removeAll() }
                // An unreadable history may hide recent work: automatic whole-project moves fail closed.
                if !discovery.issues.isEmpty && scope == .wholeProject { result.items.removeAll(); result.issues += discovery.issues }
                return (result, links, discovery)
            }.value
            mergeDiscoveredProjects(output.2.projects)
            projectScan = output.0; projectScanLinks = output.1; projectScanDays = days; projectScanScope = scope; projectScanRequiresRemoteBackup = requireRemote; projectScanDate = Date()
            projectSummary = "\(projectScan.items.count)개 정리 후보 · " + DisplayFormat.bytes(projectScan.totalBytes)
            finish(projectScan.cancelled, issues: projectScan.issues)
        }
    }
    func runProjectCleanup() {
        guard !busy, !projectScan.cancelled, !projectScan.items.isEmpty, projectScanDate != nil else { return }
        let enabledIDs = Set(selectedProjects.map(\.id))
        guard projectScanScope == projectCleanupScope, projectScanDays == projectRetentionDays, projectScanRequiresRemoteBackup == projectRequireRemoteBackup,
              projectScanLinks.allSatisfy({ enabledIDs.contains($0.id) }) else {
            banner = "정리 대상 또는 설정이 바뀌었어요. 다시 검사해 주세요."; return
        }
        let items = projectScan.items; let links = projectScanLinks; let allLinks = linkedProjects; let days = projectScanDays; let scope = projectScanScope; let requireRemote = projectScanRequiresRemoteBackup
        if !confirm("AI 프로젝트 정리", message: (scope == .wholeProject && !requireRemote ? "원격 저장 여부와 관계없이 로컬 코드·파일을 정리합니다.\n" : "") + "\(days)일 이상 업데이트되지 않은 \(items.count)개 항목의 \(scope.title)를 휴지통으로 이동합니다. 휴지통에서 복원할 수 있습니다.", action: "휴지통으로 이동", destructive: true, paths: items.map(\.id)) { return }
        let spaceMeasurement = CleanupSpaceMeasurement()
        operationBusy = true; operationLabel = "프로젝트 상태를 다시 확인하고 이동하는 중…"
        Task {
            var records: [ActionRecord] = []
            var sourceStates: [String: ProjectSourceState] = [:]
            for item in items {
                let applicationTools = aiApplicationTools; let uid = getuid()
                let priorStates = sourceStates
                let retained = duplicateOriginals.values.map { $0.url.path } + similarOriginals.map { $0.url.path } + [Bundle.main.bundleURL.path]
                let output = await Task.detached(priority: .utility) {
                    var states = priorStates
                    do {
                        let token = ScanToken()
                        let discovery = ProjectDiscovery.discover(token: token)
                        if scope == .wholeProject && !discovery.issues.isEmpty { throw DonyError.unsupported }
                        let owners = links.filter { project in item.url.path == project.path || FileSafety.isWithin(item.url, root: URL(fileURLWithPath: project.path)) }
                        guard !owners.isEmpty else { throw DonyError.unsafePath }
                        if scope == .wholeProject {
                            guard GitBackup.structuralCheck(root: item.url).verified else { throw DonyError.unsupported }
                            if requireRemote, !GitBackup.check(root: item.url).verified { throw DonyError.unsupported }
                        }
                        // Sampling follows all potentially slow metadata/network probes.
                        let fresh = SystemSampler().sample()
                        let processes = fresh.processes
                        let tools = Set(AITool.usage(processes, currentUID: uid, applicationTools: applicationTools).map(\.tool))
                        var active = ProjectDiscovery.activePaths(processes: processes, currentUID: getuid()) + retained
                        for var project in owners {
                            if (allLinks + discovery.projects).contains(where: { $0.path == project.path && tools.contains($0.tool) }) { active.append(project.path) }
                            project.lastActivity = ([project.lastActivity].compactMap { $0 } + discovery.projects.filter { $0.path == project.path }.compactMap(\.lastActivity)).max()
                            if scope != .wholeProject && states[project.path] == nil {
                                try ProjectCleanup.validate(item, project: project, days: days, scope: scope, activePaths: active, runningTools: tools, token: token)
                                let removing = items.filter { FileSafety.isWithin($0.url, root: URL(fileURLWithPath: project.path)) }
                                states[project.path] = try ProjectCleanup.captureSourceState(project: project, removing: removing, scope: scope, token: token)
                            }
                            try ProjectCleanup.validate(item, project: project, days: days, scope: scope, activePaths: active, runningTools: tools, token: token, sourceState: states[project.path])
                        }
                        return (TrashService.move(item, token: token, beforeMutation: { spaceMeasurement.captureBeforeMutation() }), states)
                    } catch { return (ActionRecord(kind: "휴지통 이동", sourcePath: item.id, trashPath: nil, bytes: 0, success: false, message: "AI 프로젝트 보호: " + error.localizedDescription), priorStates) }
                }.value
                records.append(output.0); sourceStates = output.1
            }
            let error = append(records)
            await measureCleanupOutcome(records: records, before: spaceMeasurement.beforeAvailable)
            let successful = records.filter(\.success)
            let summary = "AI 프로젝트: \(successful.count)개 · " + DisplayFormat.bytes(successful.reduce(0) { $0 + $1.bytes }) + " 휴지통 이동 · \(records.count - successful.count)개 건너뜀"
            projectSummary = OperationFeedback.compose(summary: summary, historyError: error); banner = projectSummary
            projectScan = ScanResult(); projectScanDate = nil; operationBusy = false; scanEpoch = UUID(); sample()
        }
    }
}
