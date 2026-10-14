import SwiftUI
import AppKit
import DonyCore

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var clipboard: ClipboardController
    private let titles = ["Mac 권한 허용", "개발 도구 연결", "프로젝트 연결", "준비 완료"]
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
        return AITool.allCases.filter { $0 != .other && (running.contains($0) || DevelopmentRuntime.installed($0)) }
    }
    private var otherTools: [AITool] { AITool.allCases.filter { !detectedTools.contains($0) } }
    private var projectPaths: [String] { Array(Set(model.linkedProjects.map(\.path))).sorted() }
    private func projectEnabled(_ path: String) -> Binding<Bool> {
        Binding(get: { model.linkedProjects.contains { $0.path == path && $0.enabled } }, set: { enabled in
            for index in model.linkedProjects.indices where model.linkedProjects[index].path == path { model.linkedProjects[index].enabled = enabled }
            model.saveProjectSettings()
        })
    }
    var body: some View {
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
                        Text(detectedTools.isEmpty ? "이 Mac에서 개발 도구를 찾지 못했어요. 아래에서 직접 고를 수 있어요." : "이 Mac에서 찾은 개발 도구 \(detectedTools.count)개를 연결해요. 연결한 도구의 작업 이력과 캐시를 개발 화면에서 정리해요.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                        if !detectedTools.isEmpty { ToolSelectionView(selection: $model.connectedTools, statuses: model.toolStatuses, tools: detectedTools) }
                        DisclosureGroup("다른 도구 직접 선택 \(otherTools.count)개") {
                            ToolSelectionView(selection: $model.connectedTools, statuses: model.toolStatuses, tools: otherTools).padding(.top, 12)
                        }.font(Theme.font(13, weight: .medium)).tint(Theme.secondary)
                        HStack {
                            Text("\(model.connectedTools.count)개 연결").font(Theme.font(14, weight: .semibold))
                            Spacer()
                            DonyTextAction(title: "다시 감지") { model.refreshToolConnections() }
                        }
                    case 2:
                        HStack {
                            Text(model.busy ? "작업 이력과 실행 중인 도구에서 프로젝트를 찾는 중…" : "\(projectPaths.count)개 프로젝트를 찾았어요. 정리할 프로젝트만 켜 두세요.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                            Spacer()
                            Button("폴더 추가") { model.addProjects(tools: model.connectedTools) }.buttonStyle(QuietButton()).disabled(model.connectedTools.isEmpty || model.busy)
                            Button("다시 찾기") { model.saveConnectedTools(); model.discoverProjects(includeInventory: false) }.buttonStyle(QuietButton()).disabled(model.busy)
                        }
                        if projectPaths.isEmpty {
                            Text(model.busy ? "" : "찾은 프로젝트가 없어요. 폴더 추가로 직접 연결하거나 나중에 개발 화면에서 연결할 수 있어요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(projectPaths, id: \.self) { path in
                                    HStack(spacing: 12) {
                                        Toggle("정리 대상 " + URL(fileURLWithPath: path).lastPathComponent, isOn: projectEnabled(path)).toggleStyle(DonyCheckbox()).labelsHidden()
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(URL(fileURLWithPath: path).lastPathComponent).font(Theme.font(13, weight: .medium)).lineLimit(1)
                                            Text(path).font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle).help(path)
                                        }
                                        Spacer()
                                        Text(Array(Set(model.linkedProjects.filter { $0.path == path }.map { $0.tool.title })).sorted().joined(separator: " · ")).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1)
                                    }.frame(height: Theme.listRowHeight)
                                    Divider()
                                }
                            }.panel(20)
                        }
                        HStack { Text("보관 기간").font(Theme.font(14)); Spacer(); Text("\(model.projectRetentionDays)일").font(Theme.font(16, weight: .semibold)) }
                        DonyChoices(options: ["1일", "2일", "3일", "7일", "14일", "30일"], selection: Binding(get: { "\(model.projectRetentionDays)일" }, set: { model.projectRetentionDays = Int($0.dropLast()) ?? 14; model.saveProjectSettings() }))
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
                            summaryRow("개발 도구", "\(model.connectedTools.count)개 연결", done: !model.connectedTools.isEmpty)
                            Divider()
                            summaryRow("프로젝트", "\(Set(model.linkedProjects.filter(\.enabled).map(\.path)).count)개 정리 대상", done: !model.linkedProjects.isEmpty)
                        }.panel(20)
                        Text("캐릭터").font(Theme.font(14, weight: .semibold))
                        DonyChoices(options: ["컬러", "흑백"], selection: Binding(get: { model.characterMode.title }, set: { model.setCharacterMode($0 == "흑백" ? .monochrome : .color) }))
                        CharacterPreviewView(mode: model.characterMode)
                    }
                }.padding(24)
            }
            HStack {
                if model.setupStep > 0 { Button("이전") { model.setupStep -= 1 }.buttonStyle(QuietButton()) }
                Spacer(); Text("\(model.setupStep + 1) / 4").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                Button(model.setupStep == 3 ? "시작하기" : "다음") {
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
                model.refreshToolConnections()
                if Bundle.main.object(forInfoDictionaryKey: "DonyReviewFixture") == nil, FirstLaunchSetup.claimPermissionRequests() { model.requestSelectedPermissions(notifications: true, paste: true, clipboard: clipboard) }
                else { model.refreshAccess() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshAccess(); model.refreshToolConnections() }
            .onChange(of: model.setupStep) { _, value in
                if value == 0 { model.refreshToolConnections(); model.refreshAccess() }
                if value == 2, !model.busy { model.saveConnectedTools(); model.discoverProjects(includeInventory: false) }
            }
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
