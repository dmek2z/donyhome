import SwiftUI
import AppKit
import DonyCore

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    private let titles = ["개발 도구 연결", "프로젝트 연결", "권한 확인", "캐릭터 설정"]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(nsImage: CodingCharacter.developerAvatar).resizable().interpolation(.none).frame(width: 30, height: 30)
                Text("도니클린 시작하기").font(Theme.font(21, weight: .bold))
                Spacer(); Button("나중에") { model.completeOnboarding() }.buttonStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.secondary)
            }.padding(24)
            HStack(spacing: 8) {
                ForEach(0..<4) { index in Capsule().fill(index <= model.setupStep ? Theme.primary : Theme.line).frame(height: 4) }
            }.padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(titles[model.setupStep]).font(Theme.font(24, weight: .bold))
                    switch model.setupStep {
                    case 0:
                        HStack {
                            Text("여러 도구를 함께 선택하세요").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                            Spacer(); Button("전체 선택") { model.connectedTools = Set(AITool.allCases) }.buttonStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.primary)
                            Button("선택 해제") { model.connectedTools.removeAll() }.buttonStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        }
                        ToolSelectionView(selection: $model.connectedTools, statuses: model.toolStatuses)
                        Button("다시 감지") { model.refreshToolConnections() }.buttonStyle(QuietButton())
                    case 1:
                        HStack {
                            Button("폴더 선택") { model.addProjects(tools: model.connectedTools) }.buttonStyle(PrimaryButton()).disabled(model.connectedTools.isEmpty || model.busy)
                            Button("자동으로 찾기") { model.saveConnectedTools(); model.discoverProjects() }.buttonStyle(QuietButton()).disabled(model.busy)
                        }
                        Text("\(Set(model.linkedProjects.map(\.path)).count)개 프로젝트 연결").font(Theme.font(16, weight: .semibold))
                        ForEach(Array(Set(model.linkedProjects.map(\.path))).sorted(), id: \.self) { path in Text(path).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle) }
                        HStack { Text("보관 기간").font(Theme.font(14)); Spacer(); Text("\(model.projectRetentionDays)일").font(Theme.font(16, weight: .semibold)) }
                        DonyChoices(options: ["1일", "2일", "3일", "7일", "14일", "30일"], selection: Binding(get: { "\(model.projectRetentionDays)일" }, set: { model.projectRetentionDays = Int($0.dropLast()) ?? 14; model.saveProjectSettings() }))
                        Text("자동 정리는 개발 메뉴에서 켤 수 있어요").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    case 2:
                        permission("알림", status: model.notificationStatus, action: "허용 요청") { model.setNotifications(true) }
                        permission("프로젝트 폴더 접근", status: "폴더 선택 시 승인", action: "폴더 선택") { model.addProjects(tools: model.connectedTools) }
                        permission("전체 디스크 접근", status: "보호된 캐시 검사 시 필요", action: "시스템 설정") { model.openPrivacySettings() }
                        permission("파일 및 폴더", status: "macOS 승인 확인", action: "시스템 설정") { model.openFilePermissions() }
                        Toggle("로그인할 때 실행", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).toggleStyle(DonySwitch()).padding(20).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                        Text("관리자 인증은 유지보수 실행 시 요청됩니다").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    default:
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
                    if model.setupStep < 3 { model.setupStep += 1 } else { model.completeOnboarding() }
                }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.padding(24)
        }.frame(width: 700, height: 620).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
            .onAppear { model.refreshToolConnections() }
            .onChange(of: model.setupStep) { _, value in if value == 2 { model.refreshToolConnections() } }
            .onChange(of: model.notifyEnabled) { _, _ in model.refreshToolConnections() }
    }
    private func permission(_ title: String, status: String, action: String, run: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(Theme.font(14, weight: .medium)); Text(status).font(Theme.font(11)).foregroundStyle(Theme.secondary) }
            Spacer(); Button(action, action: run).buttonStyle(QuietButton())
        }.padding(20).frame(maxWidth: .infinity).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
