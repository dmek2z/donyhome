import SwiftUI
import AppKit
import DonyCore

struct AIProjectsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = "AI 도구"
    @State private var tool = AITool.codex
    private var projects: [LinkedProject] { model.linkedProjects.filter { model.projectSource == "모두" || $0.discovered == (model.projectSource == "작업 이력") } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "개발")
            DonyTabs(options: ["AI 도구", "프로젝트"], selection: $tab)
            if tab == "AI 도구" {
                usagePanel
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("프로젝트 정리").font(Theme.font(17, weight: .semibold))
                        Text("\(model.selectedProjects.count)개 선택 · \(model.projectRetentionDays)일 보관").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("프로젝트 관리") { tab = "프로젝트" }.buttonStyle(QuietButton())
                }.frame(maxWidth: .infinity, alignment: .leading).panel()
            } else {
                settingsPanel
                projectsPanel
                if let summary = model.projectSummary { Text(summary).font(Theme.font(12)).foregroundStyle(Theme.secondary) }
                if !model.projectScan.items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("정리 후보 \(model.projectScan.items.count)개").font(Theme.font(17, weight: .semibold))
                            Spacer()
                            Text(DisplayFormat.bytes(model.projectScan.totalBytes)).font(Theme.font(15, weight: .semibold))
                        }
                        ForEach(model.projectScan.items) { item in Text(item.id).font(Theme.font(11)).foregroundStyle(Theme.secondary).textSelection(.enabled) }
                        HStack { Spacer(); Button("휴지통으로 이동") { model.runProjectCleanup() }.buttonStyle(PrimaryButton()).disabled(model.busy || model.projectScan.cancelled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                IssuesView(issues: model.projectScan.issues)
            }
        }
        .onChange(of: model.projectRetentionDays) { _, _ in model.saveProjectSettings() }
        .onChange(of: model.projectSource) { _, _ in model.saveProjectSettings() }
        .onChange(of: model.projectCleanupScope) { _, _ in model.setProjectAutomation(false); model.saveProjectSettings() }
    }
    private var usagePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI 도구 사용량").font(Theme.font(18, weight: .semibold))
                Spacer(); Chip(text: "메모리 " + model.snapshot.pressure.label, color: model.pressureColor)
            }
            if model.aiUsage.isEmpty { Text("실행 중인 AI 도구가 없어요").font(Theme.font(14)).foregroundStyle(Theme.secondary).padding(.vertical, 24) }
            ForEach(model.aiUsage) { usage in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(usage.tool.title).font(Theme.font(15, weight: .semibold))
                        Text("\(usage.processes.count)개 프로세스").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Text(DisplayFormat.bytes(usage.bytes)).font(Theme.font(18, weight: .semibold)).monospacedDigit()
                    Button("종료") { model.quitSelected(usage.processes.filter { model.canQuit($0) }) }.buttonStyle(QuietButton()).disabled(model.busy || !usage.processes.contains { model.canQuit($0) })
                }.padding(.vertical, 8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("정리 설정").font(Theme.font(18, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                settingLabel("프로젝트 찾기")
                DonyChoices(options: ["직접 등록", "작업 이력", "모두"], selection: $model.projectSource).disabled(model.busy)
            }
            VStack(alignment: .leading, spacing: 10) {
                settingLabel("AI 도구")
                DonyChoices(options: AITool.allCases.map(\.title), selection: Binding(get: { tool.title }, set: { title in if let value = AITool.allCases.first(where: { $0.title == title }) { tool = value } })).disabled(model.busy)
                HStack {
                    Button("폴더 연결") { model.addProject(tool: tool) }.buttonStyle(QuietButton()).disabled(model.busy)
                    if model.projectSource != "직접 등록" { Button("작업 이력에서 찾기") { model.discoverProjects() }.buttonStyle(QuietButton()).disabled(model.busy) }
                    Spacer()
                }
                if model.projectSource != "직접 등록" { Text("자동 수집: Codex · Claude Code · Cursor").font(Theme.font(11)).foregroundStyle(Theme.secondary) }
            }
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
                DonyChoices(options: ["빌드 · 캐시만", "프로젝트 전체"], selection: Binding(get: { model.projectCleanupScope == .generated ? "빌드 · 캐시만" : "프로젝트 전체" }, set: { model.projectCleanupScope = $0 == "프로젝트 전체" ? .wholeProject : .generated })).disabled(model.busy)
                if model.projectCleanupScope == .wholeProject { Text("소스 코드와 Git 기록 포함").font(Theme.font(12)).foregroundStyle(Theme.amber) }
            }
            Divider()
            Toggle("메모리 압박 30초 지속 시 자동 정리", isOn: Binding(get: { model.projectCleanupEnabled }, set: { model.setProjectAutomation($0) })).toggleStyle(DonySwitch()).disabled(model.busy)
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private var projectsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("프로젝트").font(Theme.font(18, weight: .semibold))
                Text("\(projects.count)").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("후보 검사") { model.scanAIProjects() }.buttonStyle(QuietButton()).disabled(model.busy || model.selectedProjects.isEmpty)
            }
            if projects.isEmpty { Text("연결된 프로젝트가 없어요").font(Theme.font(14)).foregroundStyle(Theme.secondary).padding(.vertical, 20) }
            ForEach(projects) { project in
                HStack(spacing: 12) {
                    Toggle("정리 대상 " + URL(fileURLWithPath: project.path).lastPathComponent, isOn: Binding(get: { model.linkedProjects.first(where: { $0.id == project.id })?.enabled ?? false }, set: { enabled in if let index = model.linkedProjects.firstIndex(where: { $0.id == project.id }) { model.linkedProjects[index].enabled = enabled; model.saveProjectSettings() } })).labelsHidden().toggleStyle(DonyCheckbox()).disabled(model.busy)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(URL(fileURLWithPath: project.path).lastPathComponent).font(Theme.font(14, weight: .medium))
                        Text(project.path).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle).help(project.path)
                    }
                    Spacer(minLength: 12)
                    Chip(text: project.tool.title, color: Theme.secondary)
                    Button { model.linkedProjects.removeAll { $0.id == project.id }; model.saveProjectSettings() } label: { DonyIcon("xmark", size: 14).foregroundStyle(Theme.secondary).frame(width: 28, height: 28) }.buttonStyle(.plain).help("연결 해제").accessibilityLabel("연결 해제 " + project.path).disabled(model.busy)
                }.padding(.vertical, 8)
                if project.id != projects.last?.id { Divider() }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private func settingLabel(_ title: String) -> some View { Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.secondary) }
}
