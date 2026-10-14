import SwiftUI
import AppKit
import DonyCore

struct PermissionsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var clipboard: ClipboardController
    @State private var requestNotifications = true
    @State private var requestPaste = true
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
                        HStack { Spacer(); Button("권한 설정 시작") { model.requestSelectedPermissions(notifications: requestNotifications, paste: requestPaste, clipboard: clipboard) }.buttonStyle(QuietButton()).disabled(model.requestingPermissions) }
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
                Button(model.restartNeeded ? (model.scanAfterPermissions ? "재실행하고 검사" : "재실행") : (model.scanAfterPermissions ? "검사 시작" : "완료")) { model.finishPermissions() }.buttonStyle(PrimaryButton()).disabled(model.checkingAccess || model.busy || model.requestingPermissions)
            }.padding(24)
        }.frame(width: 620, height: 680).foregroundStyle(Theme.ink).font(Theme.font(14)).background(Theme.canvas).preferredColorScheme(.light)
        .onAppear { model.refreshAccess(); model.refreshToolConnections() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshAccess(); model.refreshToolConnections() }
    }
}

struct PermissionChecklist: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var clipboard: ClipboardController
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("전체 디스크 접근", detail: model.diskAccess == .unavailable ? "보호된 파일 접근을 확인하지 못했어요" : nil, state: model.diskAccess.title, allowed: model.diskAccess == .allowed, action: "설정 열기") { model.preparePermissionSettings() }
            ForEach([("다운로드", "Downloads"), ("데스크탑", "Desktop"), ("문서", "Documents")], id: \.1) { name, directory in
                Divider()
                let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(directory).path
                let access = model.folderAccess[path] ?? .unavailable
                row(name, state: access.title, allowed: access == .allowed, action: "설정 열기") { model.preparePermissionSettings(filesOnly: true) }
            }
            if !["Downloads", "Desktop", "Documents"].contains(where: { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0).path == model.folder.path }) {
                Divider()
                let access = model.folderAccess[model.folder.path] ?? .unavailable
                row("검사 폴더", detail: model.folder.lastPathComponent, state: access.title, allowed: access == .allowed, action: "폴더 선택") { model.chooseFolder() }
            }
            Divider()
            row("알림", state: model.notificationStatus, allowed: model.notificationStatus == "허용됨", checking: false, action: ["허용됨", "꺼짐"].contains(model.notificationStatus) ? "설정 열기" : "허용 요청") {
                if ["허용됨", "꺼짐"].contains(model.notificationStatus) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
                else { model.setNotifications(true); model.refreshToolConnections() }
            }
            Divider()
            row("손쉬운 사용", detail: clipboard.accessibilityAllowed ? nil : "시스템 설정 목록에 DonyHome이 이미 켜져 있는데도 이 상태라면 이전 빌드의 항목이에요. 목록에서 DonyHome을 선택해 −로 지운 뒤 아래 버튼으로 다시 허용해 주세요.", state: clipboard.accessibilityAllowed ? "허용됨" : "권한 필요", allowed: clipboard.accessibilityAllowed, checking: false, action: "설정 열기") {
                if clipboard.accessibilityAllowed { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                else { clipboard.requestAccessibility() }
            }

        }.panel(20)
    }
    private func row(_ title: String, detail: String? = nil, state: String, allowed: Bool, checking: Bool = true, action: String, run: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.font(14, weight: .medium))
                if let detail { Text(detail).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(3).truncationMode(.middle).fixedSize(horizontal: false, vertical: true).help(detail) }
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: checking && model.checkingAccess ? "clock" : allowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                Text(checking && model.checkingAccess ? "확인 중" : state)
            }.font(Theme.font(12, weight: .medium)).foregroundStyle(checking && model.checkingAccess ? Theme.secondary : allowed ? Theme.success : Theme.amber)
            Button(action: run) { Text(action).frame(width: 104) }.buttonStyle(QuietButton())
        }.frame(minHeight: Theme.listRowHeight)
    }
}
