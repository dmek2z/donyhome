import SwiftUI
import AppKit
import DonyCore

struct PermissionsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var clipboard: ClipboardController
    @State private var requestNotifications = false
    @State private var requestPaste = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("권한 설정").font(Theme.font(22, weight: .bold))
                Spacer()
                Button("나중에") { model.cancelPermissions() }.buttonStyle(QuietButton())
            }.padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("권한을 모두 설정한 뒤 한 번만 다시 열어요.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                    PermissionChecklist()
                    VStack(alignment: .leading, spacing: 16) {
                        Text("함께 사용할 기능").font(Theme.font(16, weight: .semibold))
                        Toggle("과부하 알림", isOn: $requestNotifications).toggleStyle(DonySwitch())
                        Toggle("클립보드 바로 붙여넣기", isOn: $requestPaste).toggleStyle(DonySwitch())
                        HStack { Spacer(); Button("선택한 권한 요청") { model.requestSelectedPermissions(notifications: requestNotifications, paste: requestPaste, clipboard: clipboard) }.buttonStyle(QuietButton()) }
                    }.panel(20)
                    if let error = model.permissionError { Text(error).font(Theme.font(12)).foregroundStyle(Theme.amber) }
                    if !model.accessReport.deniedPaths.isEmpty {
                        DisclosureGroup("접근할 수 없는 경로 \(model.accessReport.deniedPaths.count)개") {
                            ForEach(model.accessReport.deniedPaths, id: \.self) { Text($0).font(Theme.font(11)).foregroundStyle(Theme.secondary).textSelection(.enabled) }
                        }.font(Theme.font(12))
                    }
                    if model.restartNeeded {
                        Text("macOS가 재실행을 물으면 ‘나중에’를 선택하고 나머지 권한도 설정하세요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            HStack {
                Button("상태 확인") { model.refreshAccess(); model.refreshToolConnections() }.buttonStyle(QuietButton()).disabled(model.checkingAccess)
                Spacer()
                Button(model.restartNeeded ? (model.scanAfterPermissions ? "재실행하고 검사" : "재실행") : (model.scanAfterPermissions ? "검사 시작" : "완료")) { model.finishPermissions() }.buttonStyle(PrimaryButton()).disabled(model.checkingAccess || model.busy)
            }.padding(24)
        }.frame(width: 620, height: 680).foregroundStyle(Theme.ink).font(Theme.font(14)).background(Theme.canvas).preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshAccess(); model.refreshToolConnections() }
    }
}

struct PermissionChecklist: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var clipboard: ClipboardController
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("전체 디스크 접근", status: model.checkingAccess ? "확인 중" : model.accessReport.deniedPaths.isEmpty ? "보호된 파일 검사에 필요" : "접근 거부 \(model.accessReport.deniedPaths.count)개", action: "설정 열기") { model.preparePermissionSettings() }
            Divider()
            row("파일 및 폴더", status: model.folder.lastPathComponent + " · 검사 폴더", action: "설정 열기") { model.preparePermissionSettings(filesOnly: true) }
            Divider()
            row("알림", status: model.notificationStatus + " · 선택", action: "허용 요청") { model.setNotifications(true); model.refreshToolConnections() }
            Divider()
            row("손쉬운 사용", status: clipboard.accessibilityAllowed ? "허용됨 · 붙여넣기" : "바로 붙여넣기에 필요 · 선택", action: "허용 요청") { clipboard.requestAccessibility() }
        }.panel(20)
    }
    private func row(_ title: String, status: String, action: String, run: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(Theme.font(14, weight: .medium)); Text(status).font(Theme.font(11)).foregroundStyle(Theme.secondary) }
            Spacer()
            Button(action: run) { Text(action).frame(width: 104) }.buttonStyle(QuietButton())
        }.frame(minHeight: 64)
    }
}
