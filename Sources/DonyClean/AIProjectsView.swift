import SwiftUI
import AppKit
import DonyCore

struct AIProjectsView: View {
    @EnvironmentObject var model: AppModel
    private var tab: String { model.developmentMode }
    @State private var projectTools: Set<AITool> = [.codex]
    private var projects: [LinkedProject] { model.linkedProjects.filter { model.projectSource == "모두" || $0.discovered == (model.projectSource == "작업 이력") } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "개발")
            DonyTabs(options: ["프로젝트", "연동", "캐시"], selection: $model.developmentMode)
            if tab == "연동" {
                integrationPanel
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("프로젝트 정리").font(Theme.font(17, weight: .semibold))
                        Text("\(Set(model.selectedProjects.map(\.path)).count)개 선택 · \(model.projectRetentionDays)일 보관").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("프로젝트 관리") { model.developmentMode = "프로젝트" }.buttonStyle(QuietButton())
                }.frame(maxWidth: .infinity, alignment: .leading).panel()
            } else if tab == "캐시" { DeveloperView() } else {
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
                IssuesView(issues: model.projectScan.issues)
            }
        }
        .onAppear { model.refreshToolConnections(); projectTools = model.connectedTools; if model.connectionCheckedAt == nil && !model.busy { model.discoverProjects(includeInventory: false) } }
        .onChange(of: projectTools) { _, value in model.connectedTools = value; model.saveConnectedTools() }
        .onChange(of: model.projectRetentionDays) { _, _ in model.saveProjectSettings() }
        .onChange(of: model.projectRequireRemoteBackup) { _, _ in model.setProjectAutomation(false); model.saveProjectSettings() }
        .onChange(of: model.projectSource) { _, _ in model.saveProjectSettings() }
        .onChange(of: model.projectCleanupScope) { _, _ in model.setProjectAutomation(false); model.saveProjectSettings() }
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
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tool.title).font(Theme.font(14, weight: .semibold))
                        Text(model.toolStatuses[tool] ?? "아직 검사하지 않음").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Text(tool == .chatGPT ? "폴더 연결" : [.codex, .claude, .cursor].contains(tool) ? "로컬 작업 이력" : [.orca, .herdr, .cmux, .tmux].contains(tool) ? "로컬 CLI" : "실행 경로").font(Theme.font(12)).foregroundStyle(Theme.secondary)
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
                if model.projectSource != "직접 등록" { Text("작업 이력 · 실행 중인 터미널 프로젝트").font(Theme.font(11)).foregroundStyle(Theme.secondary) }
                }.padding(.top, 12)
            }.font(Theme.font(14, weight: .medium)).tint(Theme.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    settingLabel("보관 기간")
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
            Divider()
            Toggle("메모리 압박 30초 지속 시 자동 정리", isOn: Binding(get: { model.projectCleanupEnabled }, set: { model.setProjectAutomation($0) })).toggleStyle(DonySwitch()).disabled(model.busy)
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private var projectsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("프로젝트 파일").font(Theme.font(18, weight: .semibold))
                Text("\(Set(projects.map(\.path)).count)").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("정리 대상 확인") { model.scanAIProjects() }.buttonStyle(QuietButton()).disabled(model.busy || model.selectedProjects.isEmpty)
            }
            HStack {
                Spacer()
                Button("전체 선택") { selectProjects(true) }.disabled(model.busy).buttonStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.primary)
                Button("선택 해제") { selectProjects(false) }.disabled(model.busy).buttonStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.secondary)
            }
            if projects.isEmpty { Text("연결된 프로젝트가 없어요").font(Theme.font(14)).foregroundStyle(Theme.secondary).padding(.vertical, 20) }
            ForEach(Array(Set(projects.map(\.path))).sorted(), id: \.self) { path in
                let links = projects.filter { $0.path == path }
                let inventory = model.projectInventory.first { $0.path == path }
                HStack(spacing: 12) {
                    Toggle("정리 대상 " + URL(fileURLWithPath: path).lastPathComponent, isOn: Binding(get: { links.contains { $0.enabled } }, set: { enabled in
                        let ids = Set(links.map(\.id))
                        for index in model.linkedProjects.indices where ids.contains(model.linkedProjects[index].id) { model.linkedProjects[index].enabled = enabled }
                        model.saveProjectSettings()
                    })).labelsHidden().toggleStyle(DonyCheckbox()).disabled(model.busy)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(URL(fileURLWithPath: path).lastPathComponent).font(Theme.font(14, weight: .medium))
                        Text(path).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle).help(path)
                    }
                    Spacer(minLength: 12)
                    if let inventory {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text((inventory.issues.isEmpty ? "" : "일부 결과 · ") + "\(inventory.files)개 파일 · " + DisplayFormat.bytes(inventory.bytes)).font(Theme.font(13, weight: .medium))
                            Text(inventory.managedWorktree ? "관리 도구 worktree · 보호" : "AI 컨텍스트 \(inventory.contextFiles)개 · 생성물 " + DisplayFormat.bytes(inventory.generatedBytes)).font(Theme.font(11)).foregroundStyle(Theme.secondary)
                            Text(inventory.backup.reason).font(Theme.font(10)).foregroundStyle(inventory.backup.verified ? Theme.success : Theme.secondary)
                            if let date = inventory.lastActivity { Text(date, format: .dateTime.month().day().hour().minute()).font(Theme.font(10)).foregroundStyle(Theme.secondary) }
                        }
                    }
                    let names = Array(Set(links.map { $0.tool.title })).sorted()
                    Chip(text: names.prefix(2).joined(separator: " · ") + (names.count > 2 ? " +\(names.count - 2)" : ""), color: Theme.secondary)
                    Button { let ids = Set(links.map(\.id)); model.linkedProjects.removeAll { ids.contains($0.id) }; model.saveProjectSettings() } label: { DonyIcon("xmark", size: 14).foregroundStyle(Theme.secondary).frame(width: 28, height: 28) }.buttonStyle(.plain).help("연결 해제").accessibilityLabel("연결 해제 " + path).disabled(model.busy)
                }.frame(minHeight: 72)
                Divider()
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private func selectProjects(_ enabled: Bool) {
        let paths = Set(projects.map(\.path))
        for index in model.linkedProjects.indices where paths.contains(model.linkedProjects[index].path) { model.linkedProjects[index].enabled = enabled }
        model.saveProjectSettings()
    }
    private func settingLabel(_ title: String) -> some View { Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.secondary) }
}
