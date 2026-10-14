import SwiftUI
import AppKit
import DonyCore

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var clipboard: ClipboardController
    private let titles = ["Mac 권한 허용", "개발 도구 탐색", "프로젝트 동기화", "준비 완료"]
    private let permissionFolders = ["Downloads", "Desktop", "Documents"]
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    /// 온보딩에서 확인하는 권한 6개의 허용 현황.
    private var allowedPermissions: Int {
        [model.diskAccess == .allowed, model.notificationStatus == "허용됨", clipboard.accessibilityAllowed].filter { $0 }.count
            + permissionFolders.filter { model.folderAccess[home.appendingPathComponent($0).path] == .allowed }.count
    }
    private let totalPermissions = 6
    private var detectedTools: [AITool] {
        let running = Set(model.aiUsage.map(\.tool))
        return AITool.selectable.filter { $0 != .other && (running.contains($0) || DevelopmentRuntime.installed($0)) }
    }
    @State private var toolsPreselected = false
    private func projectCount(_ tool: AITool) -> Int { Set(model.linkedProjects.filter { $0.tool == tool }.map(\.path)).count }
    /// 이 Mac에서 쓰는 개발 도구를 찾고 연동 대상으로 선택한 뒤 도구별 프로젝트를 탐색한다.
    private func scanTools() {
        model.refreshToolConnections()
        if Bundle.main.object(forInfoDictionaryKey: "DonyReviewFixture") != nil { return }
        if !toolsPreselected { toolsPreselected = true; model.connectedTools = Set(detectedTools) }
        model.saveConnectedTools()
        if !model.busy { model.discoverProjects(includeInventory: false) }
    }
    private func toolRow(_ tool: AITool) -> some View {
        let running = model.aiUsage.contains { $0.tool == tool }
        let count = projectCount(tool)
        return HStack(spacing: 12) {
            Toggle("연동 " + tool.title, isOn: Binding(get: { model.connectedTools.contains(tool) }, set: { if $0 { model.connectedTools.insert(tool) } else { model.connectedTools.remove(tool) } })).toggleStyle(DonyCheckbox()).labelsHidden()
            ToolIcon(tool: tool, size: 30)
            Text(tool.title).font(Theme.font(14, weight: .medium))
            Spacer()
            Text((running ? "사용 중" : "설치됨") + (model.connectedTools.contains(tool) && count > 0 ? " · 프로젝트 \(count)개" : "")).font(Theme.font(12)).foregroundStyle(running ? Theme.success : Theme.secondary)
        }.frame(height: 52)
    }
    private var otherTools: [AITool] { AITool.selectable.filter { !detectedTools.contains($0) } }
    private var projectPaths: [String] { Array(Set(model.linkedProjects.map(\.path))).sorted() }
    @State private var projectQuery = ""
    @State private var showExclude = (Bundle.main.object(forInfoDictionaryKey: "DonyReviewFixture") as? String)?.hasSuffix("x") == true
    private func toolLinks(_ tool: AITool, filtered: Bool = true) -> [LinkedProject] {
        let query = projectQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        return model.linkedProjects.filter { $0.tool == tool && seen.insert($0.path).inserted && (!filtered || query.isEmpty || $0.path.lowercased().contains(query)) }.sorted { $0.path < $1.path }
    }
    private func setLinks(_ tool: AITool, path: String? = nil, enabled: Bool) {
        for index in model.linkedProjects.indices where model.linkedProjects[index].tool == tool && (path == nil || model.linkedProjects[index].path == path) { model.linkedProjects[index].enabled = enabled }
        model.saveProjectSettings()
    }
    private func linkEnabled(_ tool: AITool, _ path: String) -> Binding<Bool> {
        Binding(get: { model.linkedProjects.contains { $0.tool == tool && $0.path == path && $0.enabled } }, set: { setLinks(tool, path: path, enabled: $0) })
    }
    private func toolEnabled(_ tool: AITool) -> Binding<Bool> {
        Binding(get: { let all = toolLinks(tool, filtered: false); return !all.isEmpty && all.allSatisfy { link in model.linkedProjects.contains { $0.tool == tool && $0.path == link.path && $0.enabled } } }, set: { setLinks(tool, enabled: $0) })
    }
    private var syncedProjectCount: Int { Set(model.linkedProjects.filter(\.enabled).map(\.path)).count }
    private var excludePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { showExclude.toggle() } } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("정리에서 제외할 프로젝트").font(Theme.font(16, weight: .semibold))
                        Text("\(syncedProjectCount)개가 정리 대상이에요. 빼고 싶은 프로젝트만 체크를 끄세요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(showExclude ? "접기" : "고르기").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.primary)
                    DonyIcon("chevron.right", size: 12).foregroundStyle(Theme.primary).rotationEffect(.degrees(showExclude ? 90 : 0))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("정리에서 제외할 프로젝트 " + (showExclude ? "접기" : "고르기"))
            if showExclude {
                DonySearchField(placeholder: "프로젝트 이름·경로 검색", text: $projectQuery).padding(.top, 16)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.connectedTools.sorted { $0.title < $1.title }.filter { !toolLinks($0).isEmpty }) { tool in
                            HStack(spacing: 10) {
                                Toggle("\(tool.title) 전체", isOn: toolEnabled(tool)).toggleStyle(DonyCheckbox()).labelsHidden()
                                ToolIcon(tool: tool, size: 24)
                                Text(tool.title).font(Theme.font(14, weight: .semibold))
                                Text("\(toolLinks(tool, filtered: false).count)개").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                                Spacer()
                            }.frame(height: 48).padding(.top, 6)
                            ForEach(toolLinks(tool)) { link in
                                Divider()
                                HStack(spacing: 12) {
                                    Toggle("정리 대상 " + URL(fileURLWithPath: link.path).lastPathComponent, isOn: linkEnabled(tool, link.path)).toggleStyle(DonyCheckbox()).labelsHidden()
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(URL(fileURLWithPath: link.path).lastPathComponent).font(Theme.font(13, weight: .medium)).lineLimit(1)
                                        Text(link.path).font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle).help(link.path)
                                    }
                                    Spacer()
                                }.frame(height: 52)
                            }
                        }
                    }
                }.frame(maxHeight: 340).padding(.top, 8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
    }
    var body: some View {
        if model.introPage != nil { IntroView().environmentObject(model) } else { setupBody }
    }
    private var setupBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(nsImage: CodingCharacter.developerAvatar).resizable().interpolation(.none).frame(width: 30, height: 30)
                Text("도니홈 시작하기").font(Theme.font(21, weight: .bold))
                Spacer(); Button("나중에") { model.completeOnboarding() }.buttonStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.secondary).disabled(model.requestingPermissions)
            }.padding(24)
            HStack(spacing: 8) {
                ForEach(0..<4) { index in Capsule().fill(index <= model.setupStep ? Theme.primary : Theme.line).frame(height: 4) }
            }.padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(titles[model.setupStep]).font(Theme.font(24, weight: .bold))
                    switch model.setupStep {
                    case 1:
                        HStack(spacing: 10) {
                            if model.busy { ProgressView().controlSize(.small) }
                            Text(model.busy ? "개발 도구를 탐색하고 있어요…" : detectedTools.isEmpty ? "이 Mac에서 사용 중인 개발 도구를 찾지 못했어요. 아래에서 직접 고를 수 있어요." : "사용 중인 개발 도구 \(detectedTools.count)개를 찾았어요").font(Theme.font(14, weight: .semibold))
                            Spacer()
                        }
                        if !detectedTools.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(detectedTools) { tool in
                                    toolRow(tool)
                                    if tool != detectedTools.last { Divider() }
                                }
                            }.padding(.horizontal, 20).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        DisclosureGroup("목록에 없는 도구 직접 선택 \(otherTools.count)개") {
                            ToolSelectionView(selection: $model.connectedTools, statuses: [:], tools: otherTools).padding(.top, 12)
                        }.font(Theme.font(13, weight: .medium)).tint(Theme.secondary)
                    case 2:
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                if model.busy { ProgressView().controlSize(.small) }
                                Text(model.busy ? "연동한 도구의 프로젝트를 불러오는 중…" : "프로젝트 \(projectPaths.count)개를 자동으로 동기화해요").font(Theme.font(16, weight: .semibold))
                            }
                            Text("연동한 도구에서 쓰는 프로젝트를 모두 가져오고, 새 프로젝트도 자동으로 추가돼요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                            ForEach(model.connectedTools.sorted { $0.title < $1.title }.filter { projectCount($0) > 0 }) { tool in
                                HStack { Text(tool.title).font(Theme.font(13, weight: .medium)); Spacer(); Text("\(projectCount(tool))개").font(Theme.font(13)).foregroundStyle(Theme.secondary) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 12) {
                            Text("정리 기준").font(Theme.font(16, weight: .semibold))
                            Text("마지막 작업 후 \(model.projectRetentionDays)일 동안 활동이 없으면 빌드·캐시를 정리 후보로 추천해요. 정리한 파일은 휴지통으로 가요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                            DonyChoices(options: ["3일", "7일", "14일", "30일"], selection: Binding(get: { "\(model.projectRetentionDays)일" }, set: { model.projectRetentionDays = Int($0.dropLast()) ?? 14; model.saveProjectSettings() }))
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                        excludePanel
                    case 0:
                        HStack {
                            Text("권한 \(totalPermissions)개 중 \(allowedPermissions)개 허용됨").font(Theme.font(14, weight: .semibold)).foregroundStyle(allowedPermissions == totalPermissions ? Theme.success : Theme.body)
                            Spacer()
                            Button(allowedPermissions == totalPermissions ? "모두 허용됨" : "권한 허용하기") { model.requestSelectedPermissions(notifications: true, paste: true, clipboard: clipboard) }.buttonStyle(PrimaryButton()).disabled(model.requestingPermissions || allowedPermissions == totalPermissions)
                        }
                        PermissionChecklist()
                        if let error = model.permissionError { Text(error).font(Theme.font(12)).foregroundStyle(Theme.amber) }
                        Text("시스템 창에서 직접 허용해 주세요. 전체 디스크 접근을 바꾸면 마지막에 한 번만 다시 열어요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        Toggle("로그인할 때 실행", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).toggleStyle(DonySwitch()).padding(20).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                    default:
                        VStack(spacing: 0) {
                            summaryRow("Mac 권한", "\(allowedPermissions) / \(totalPermissions) 허용", done: allowedPermissions == totalPermissions)
                            Divider()
                            summaryRow("개발 도구", "\(model.connectedTools.count)개 연동", done: !model.connectedTools.isEmpty)
                            Divider()
                            summaryRow("프로젝트", "\(Set(model.linkedProjects.filter(\.enabled).map(\.path)).count)개 자동 동기화", done: !model.linkedProjects.isEmpty)
                        }.panel(20)
                    }
                }.padding(24)
            }
            HStack {
                if model.setupStep > 0 { Button("이전") { model.setupStep -= 1 }.buttonStyle(QuietButton()) }
                Spacer(); Text("\(model.setupStep + 1) / 4").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                Button(model.setupStep == 3 ? "시작하기" : model.setupStep == 1 ? "\(model.connectedTools.count)개 도구 연동" : "다음") {
                    model.saveConnectedTools()
                    if model.setupStep < 3 {
                        if model.setupStep == 0 {
                            model.permissionSetupReviewed = true
                            UserDefaults.standard.set(true, forKey: "permissionSetupReviewed")
                        }
                        model.setupStep += 1
                    } else { model.completeOnboarding() }
                }.buttonStyle(PrimaryButton()).disabled(model.busy || model.requestingPermissions)
            }.padding(24)
        }.frame(width: 700, height: 620).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
            .onAppear {
                if model.setupStep == 1 { scanTools() } else { model.refreshToolConnections() }
                if Bundle.main.object(forInfoDictionaryKey: "DonyReviewFixture") == nil, FirstLaunchSetup.claimPermissionRequests() { model.requestSelectedPermissions(notifications: true, paste: true, clipboard: clipboard) }
                else { model.refreshAccess() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshAccess(); model.refreshToolConnections() }
            .onChange(of: model.setupStep) { _, value in
                if value == 0 { model.refreshToolConnections(); model.refreshAccess() }
                if value == 1 { scanTools() }
                if value == 2, !model.busy { model.projectSource = "모두"; model.saveProjectSettings(); model.saveConnectedTools(); model.discoverProjects(includeInventory: false) }
            }
            .onChange(of: model.busy) { _, busy in if !busy && model.setupStep == 2 { model.enableDiscoveredProjectsOnce() } }
            .onChange(of: model.notifyEnabled) { _, _ in model.refreshToolConnections() }
    }
    private func summaryRow(_ title: String, _ value: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title).font(Theme.font(14, weight: .medium))
            Spacer()
            HStack(spacing: 5) { Image(systemName: done ? "checkmark.circle.fill" : "exclamationmark.circle"); Text(value) }.font(Theme.font(12, weight: .medium)).foregroundStyle(done ? Theme.success : Theme.amber)
        }.frame(height: 48)
    }
}
