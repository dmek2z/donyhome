import SwiftUI
import AppKit
import DonyCore

struct AIProjectsView: View {
    @EnvironmentObject var model: AppModel
    private var tab: String { model.developmentMode }
    @State private var focusedProjectPath: String?
    @State private var projectTools: Set<AITool> = [.codex]
    private var projects: [LinkedProject] { model.linkedProjects.filter { model.projectSource == "모두" || $0.discovered == (model.projectSource == "작업 이력") } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "개발")
            DonyTabs(options: ["도구 정리", "작업", "연동", "프로젝트", "캐시"], selection: $model.developmentMode)
            if tab == "도구 정리" { ToolCareView() }
            else if tab == "연동" {
                integrationPanel
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("프로젝트 정리").font(Theme.font(17, weight: .semibold))
                        Text("\(Set(model.selectedProjects.map(\.path)).count)개 선택 · \(model.projectRetentionDays)일 보관").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("프로젝트 관리") { model.developmentMode = "프로젝트" }.buttonStyle(QuietButton())
                }.frame(maxWidth: .infinity, alignment: .leading).panel()
            } else if tab == "작업" { DeveloperTasksView() } else if tab == "캐시" { DeveloperView() } else {
                HStack {
                    Text("프로젝트 · 파일 · 작업 컨텍스트").font(Theme.font(17, weight: .semibold))
                    Spacer()
                    Button("프로젝트 검사") { model.discoverProjects() }.buttonStyle(PrimaryButton()).disabled(model.busy)
                }
                projectsPanel
                DisclosureGroup("정리 설정") { settingsPanel.padding(.top, 12) }.font(Theme.font(14, weight: .medium)).tint(Theme.secondary)
                if let summary = model.projectSummary { Text(summary).font(Theme.font(12)).foregroundStyle(Theme.secondary) }
                if !model.projectScan.items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("정리 후보 \(model.projectScan.items.count)개").font(Theme.font(17, weight: .semibold))
                            Spacer()
                            Text(DisplayFormat.bytes(model.projectScan.totalBytes)).font(Theme.font(15, weight: .semibold))
                        }
                        DisclosureGroup("대상 경로") { ForEach(model.projectScan.items) { item in Text(item.id).font(Theme.font(11)).foregroundStyle(Theme.secondary).textSelection(.enabled) } }.font(Theme.font(12))
                        HStack { Spacer(); Button("휴지통으로 이동") { model.runProjectCleanup() }.buttonStyle(PrimaryButton()).disabled(model.busy || model.projectScan.cancelled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                IssuesView(issues: model.connectionIssues.filter { issue in !model.projectScan.issues.contains { $0.id == issue.id } } + model.projectScan.issues)
            }
        }
        .onAppear {
            model.refreshToolConnections(); projectTools = model.connectedTools
            if !model.busy {
                if tab == "도구 정리", model.toolStorageDate == nil { model.scanToolStorage() }
                else if tab != "도구 정리", model.connectionCheckedAt == nil { model.discoverProjects(includeInventory: false) }
            }
        }
        .onChange(of: projectTools) { _, value in model.connectedTools = value; model.saveConnectedTools() }
        .onChange(of: model.projectRetentionDays) { _, _ in model.saveProjectSettings() }
        .onChange(of: model.projectRequireRemoteBackup) { _, _ in model.saveProjectSettings() }
        .onChange(of: model.projectSource) { _, _ in model.saveProjectSettings() }
        .onChange(of: model.projectCleanupScope) { _, _ in model.saveProjectSettings() }
    }
    private var integrationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("연동 상태").font(Theme.font(18, weight: .semibold))
                Spacer()
                Button("연동 확인") { model.discoverProjects() }.buttonStyle(QuietButton()).disabled(model.busy)
            }
            HStack {
                Text("연결할 도구").font(Theme.font(14, weight: .medium))
                Spacer()
                Button("자동 연결") { model.connectInstalledTools(); projectTools = model.connectedTools }.buttonStyle(QuietButton()).disabled(model.busy)
            }
            ToolSelectionView(selection: $projectTools).disabled(model.busy)
            ForEach(AITool.allCases.filter { model.connectedTools.contains($0) }) { tool in
                HStack(spacing: 12) {
                    ToolIcon(tool: tool, size: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tool.title).font(Theme.font(14, weight: .semibold))
                        Text(model.toolStatuses[tool] ?? "아직 검사하지 않음").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Text([.codex, .claude, .cursor].contains(tool) ? "로컬 작업 이력" : [.orca, .herdr, .cmux, .tmux].contains(tool) ? "로컬 CLI" : "실행 경로").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                }.frame(minHeight: 56)
                Divider()
            }
            IssuesView(issues: model.connectionIssues)
        }.panel()
    }
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("정리 설정").font(Theme.font(18, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                settingLabel("프로젝트 목록")
                DonyChoices(options: ["직접 등록", "작업 이력", "모두"], selection: $model.projectSource).disabled(model.busy)
            }
            DisclosureGroup("프로젝트 연결") {
                VStack(alignment: .leading, spacing: 10) {
                HStack {
                    settingLabel("연결할 도구")
                    Spacer()
                    Button("전체 선택") { projectTools = Set(AITool.allCases) }.buttonStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.primary)
                    Button("선택 해제") { projectTools.removeAll() }.buttonStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.secondary)
                }
                ToolSelectionView(selection: $projectTools).disabled(model.busy)
                HStack {
                    Spacer()
                    Button("폴더 연결") { model.addProjects(tools: projectTools) }.buttonStyle(QuietButton()).disabled(model.busy || projectTools.isEmpty)
                    if model.projectSource != "직접 등록" { Button("작업 이력에서 찾기") { model.discoverProjects() }.buttonStyle(QuietButton()).disabled(model.busy) }
                }
                }.padding(.top, 12)
            }.font(Theme.font(14, weight: .medium)).tint(Theme.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    settingLabel("정리 기준 · 안 쓴 기간")
                    Spacer()
                    Button("−") { model.projectRetentionDays = max(1, model.projectRetentionDays - 1) }.buttonStyle(QuietButton()).disabled(model.busy || model.projectRetentionDays == 1)
                    HStack(spacing: 6) {
                        TextField("일", value: $model.projectRetentionDays, format: .number).textFieldStyle(.plain).font(Theme.font(18, weight: .semibold)).multilineTextAlignment(.center).frame(width: 58)
                        Text("일").font(Theme.font(14)).foregroundStyle(Theme.secondary)
                    }.frame(height: 42).padding(.horizontal, 10).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 10)).disabled(model.busy)
                    Button("+") { model.projectRetentionDays = min(3650, model.projectRetentionDays + 1) }.buttonStyle(QuietButton()).disabled(model.busy || model.projectRetentionDays == 3650)
                }
                DonyChoices(options: ["1일", "2일", "3일", "7일", "14일", "30일"], selection: Binding(get: { "\(model.projectRetentionDays)일" }, set: { model.projectRetentionDays = Int($0.dropLast()) ?? 14 })).disabled(model.busy)
            }
            VStack(alignment: .leading, spacing: 10) {
                settingLabel("정리 범위")
                DonyChoices(options: ["빌드 · 캐시만", "AI 컨텍스트", "프로젝트 전체"], selection: Binding(get: { model.projectCleanupScope == .generated ? "빌드 · 캐시만" : model.projectCleanupScope == .context ? "AI 컨텍스트" : "프로젝트 전체" }, set: { model.projectCleanupScope = $0 == "프로젝트 전체" ? .wholeProject : $0 == "AI 컨텍스트" ? .context : .generated })).disabled(model.busy)
                if model.projectCleanupScope == .context { Text("프로젝트 규칙·메모리·에이전트 설정 포함 · 대화 기록 제외").font(Theme.font(12)).foregroundStyle(Theme.amber) }
                if model.projectCleanupScope == .wholeProject {
                    Toggle("원격에 보관된 프로젝트만 정리", isOn: $model.projectRequireRemoteBackup).toggleStyle(DonySwitch()).disabled(model.busy)
                    if !model.projectRequireRemoteBackup { Text("원격에 없는 로컬 코드·파일도 함께 휴지통으로 이동해요.").font(Theme.font(12)).foregroundStyle(Theme.amber) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private var projectPaths: [String] { Array(Set(projects.map(\.path))).sorted() }
    private var focusedPath: String? { if let focusedProjectPath, projectPaths.contains(focusedProjectPath) { return focusedProjectPath }; return projectPaths.first }
    private var projectsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("프로젝트 파일").font(Theme.font(18, weight: .semibold))
                Text("\(projectPaths.count)개").font(Theme.font(14)).foregroundStyle(Theme.secondary)
                Spacer()
                DonyTextAction(title: projects.contains { $0.enabled } ? "선택 해제" : "전체 선택") {
                    selectProjects(!projects.contains { $0.enabled })
                }.disabled(model.busy || projects.isEmpty)
                Button("정리 대상 확인") { model.scanAIProjects() }.buttonStyle(QuietButton()).disabled(model.busy || model.selectedProjects.isEmpty)
            }
            if projectPaths.isEmpty {
                Text("연결된 프로젝트가 없어요").font(Theme.font(14)).foregroundStyle(Theme.secondary).padding(.vertical, 20)
            } else {
                GeometryReader { geometry in
                    if geometry.size.width >= 640 {
                        HStack(alignment: .top, spacing: 20) {
                            projectList.frame(width: 270, height: 570)
                            Divider().frame(height: 570)
                            projectWorkspace.frame(width: max(0, geometry.size.width - 311), height: 570)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            projectList.frame(height: 200)
                            Divider()
                            projectWorkspace.frame(height: 337)
                        }
                    }
                }.frame(height: 570)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(projectPaths, id: \.self) { path in
                    let links = projects.filter { $0.path == path }
                    let inventory = model.projectInventory.first { $0.path == path }
                    HStack(spacing: 8) {
                        Toggle("정리 대상 " + URL(fileURLWithPath: path).lastPathComponent, isOn: Binding(get: { links.contains { $0.enabled } }, set: { enabled in setProject(path, enabled: enabled) }))
                            .labelsHidden().toggleStyle(DonyCheckbox()).disabled(model.busy)
                        Button { focusedProjectPath = path } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent).font(Theme.font(13, weight: .medium)).lineLimit(1)
                                    Text(Array(Set(links.map { $0.tool.title })).sorted().joined(separator: " · ")).font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(inventory.map { measuredBytes($0.bytes, entry: $0) } ?? "미확인").font(Theme.font(11, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading).frame(height: Theme.listRowHeight).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("프로젝트 상세 " + path).accessibilityAddTraits(focusedPath == path ? .isSelected : []).help(path)
                    }.padding(.horizontal, 8).frame(height: Theme.listRowHeight).background(focusedPath == path ? Theme.blueWash : .clear).clipShape(RoundedRectangle(cornerRadius: 10))
                    Divider()
                }
            }
        }
    }
    private var projectWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ProjectCapacityView(entries: model.projectInventory.filter { projectPaths.contains($0.path) }, selectedPath: focusedPath) { focusedProjectPath = $0 }
                Divider()
                if let path = focusedPath { projectDetail(path) }
            }.padding(.trailing, 2)
        }
    }
    @ViewBuilder private func projectDetail(_ path: String) -> some View {
        let inventory = model.projectInventory.first { $0.path == path }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(URL(fileURLWithPath: path).lastPathComponent).font(Theme.font(18, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 12)
                DonyIconMenu(title: "프로젝트 관리") {
                    Button("Finder에서 보기") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
                    Button("연결 해제") { model.linkedProjects.removeAll { $0.path == path }; model.saveProjectSettings() }
                }.disabled(model.busy)
            }
            Text(path).font(Theme.font(11)).foregroundStyle(Theme.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let entry = inventory {
                if !entry.issues.isEmpty { Chip(text: "일부 결과 · 확인 필요", color: Theme.amber) }
                VStack(spacing: 10) {
                    detailValue("프로젝트 전체", measuredBytes(entry.bytes, entry: entry) + (entry.files > 0 || entry.issues.isEmpty ? " · \(entry.files)개 파일" : ""))
                    detailValue("빌드 · 캐시", measuredBytes(entry.generatedBytes, entry: entry))
                    detailValue("AI 컨텍스트", measuredBytes(entry.contextBytes, entry: entry) + (entry.contextFiles > 0 || entry.issues.isEmpty ? " · \(entry.contextFiles)개 파일" : ""))
                    detailValue("최근 활동", activityText(entry.lastActivity))
                    detailValue("원격 보관", entry.backup.verified ? "확인됨" : "확인 필요", color: entry.backup.verified ? Theme.success : Theme.secondary)
                }
                Text(entry.backup.reason).font(Theme.font(12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 7) {
                    Text("정리 판단").font(Theme.font(13, weight: .semibold))
                    Text(reviewReason(entry)).font(Theme.font(12)).foregroundStyle(entry.managedWorktree || !entry.issues.isEmpty ? Theme.amber : Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 10))
                ForEach(entry.issues.prefix(3)) { issue in Text(issue.message).font(Theme.font(11)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true) }
            } else {
                Text("용량·최근 활동·원격 보관 상태를 아직 확인하지 않았어요.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                Text("프로젝트 검사를 실행한 뒤 정리 대상 확인으로 실제 후보를 검토해 주세요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            }
        }
    }
    private func setProject(_ path: String, enabled: Bool) {
        let ids = Set(projects.filter { $0.path == path }.map(\.id))
        for index in model.linkedProjects.indices where ids.contains(model.linkedProjects[index].id) { model.linkedProjects[index].enabled = enabled }
        model.saveProjectSettings()
    }
    private func measuredBytes(_ bytes: Int64, entry: ProjectInventoryEntry) -> String {
        if !entry.issues.isEmpty { return bytes > 0 ? "확인된 " + DisplayFormat.bytes(bytes) : "미확인" }
        return DisplayFormat.bytes(bytes)
    }
    private func detailValue(_ title: String, _ value: String, color: Color = Theme.body) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(title).font(Theme.font(12)).foregroundStyle(Theme.secondary); Spacer(minLength: 16); Text(value).font(Theme.font(12, weight: .medium)).foregroundStyle(color).multilineTextAlignment(.trailing) }
    }
    private func activityText(_ date: Date?) -> String {
        guard let date, date != .distantPast else { return "미확인" }
        let days = max(0, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0)
        return date.formatted(date: .abbreviated, time: .omitted) + " · " + (days == 0 ? "오늘" : "\(days)일 전")
    }
    private func reviewReason(_ entry: ProjectInventoryEntry) -> String {
        if entry.managedWorktree { return "관리 도구의 worktree라 보호해요. 이 목록의 오래된 활동만으로 정리하지 않아요." }
        if !entry.issues.isEmpty { return "일부 파일을 확인하지 못했어요. 권한·동기화 상태를 확인하고 다시 검사해 주세요." }
        guard let date = entry.lastActivity, date != .distantPast else { return "최근 활동을 확인하지 못했어요. 정리 대상 확인에서 파일 상태를 다시 검사해 주세요." }
        let cutoff = Date().addingTimeInterval(-Double(model.projectRetentionDays) * 86400)
        if date > cutoff { return "최근 \(model.projectRetentionDays)일 안에 활동해서 정리 추천에서 빼요. 현재 정리 범위는 \(model.projectCleanupScope.title)이에요." }
        return "\(model.projectRetentionDays)일 넘게 활동이 없어요. 정리 대상 확인에서 실행 중인 도구·파일 상태" + (model.projectCleanupScope == .wholeProject && model.projectRequireRemoteBackup ? "·원격 보관" : "") + "을 다시 확인해야 해요."
    }
    private func selectProjects(_ enabled: Bool) {
        let paths = Set(projects.map(\.path))
        for index in model.linkedProjects.indices where paths.contains(model.linkedProjects[index].path) { model.linkedProjects[index].enabled = enabled }
        model.saveProjectSettings()
    }
    private func settingLabel(_ title: String) -> some View { Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.secondary) }
}
