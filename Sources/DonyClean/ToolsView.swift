import SwiftUI
import DonyCore

struct ToolsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedSnapshot = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "유지보수")
            TrashView()
            task("DNS 캐시 초기화", detail: "DNS 변경 후 사이트가 연결되지 않을 때", icon: "arrow.clockwise", action: .flushDNS)
            task("Spotlight 재색인", detail: "파일 검색이 누락되거나 정확하지 않을 때", icon: "magnifyingglass", action: .reindexSpotlight)
            VStack(alignment: .leading, spacing: 16) {
                SettingsActionRow(title: "Time Machine 백업", actionTitle: "목록 확인", enabled: !model.busy) { model.refreshSnapshots() }
                if model.snapshotsDate == nil { EmptyView() }
                else if model.localSnapshots.isEmpty { Text("이 Mac에 저장된 백업이 없어요").font(Theme.font(13)).foregroundStyle(Theme.secondary) }
                else {
                    HStack {
                        Text("백업 시점").font(Theme.font(14))
                        Spacer()
                        DonyMenuButton(title: selectedSnapshot.isEmpty ? "선택하세요" : selectedSnapshot, width: Theme.filterWidth) {
                            Button("선택 해제") { selectedSnapshot = "" }
                            ForEach(model.localSnapshots, id: \.self) { snapshot in Button(snapshot) { selectedSnapshot = snapshot } }
                        }.disabled(model.busy).help(selectedSnapshot)
                    }
                    HStack { Text("선택한 백업 시점은 영구 제거돼요.").font(Theme.font(12)).foregroundStyle(Theme.secondary); Spacer(); Button { model.runMaintenance(.deleteSnapshot(selectedSnapshot)) } label: { Text("영구 삭제").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(!model.localSnapshots.contains(selectedSnapshot) || model.busy) }
                }
            }.panel(24)
            if let output = model.maintenanceOutput {
                DisclosureGroup("작업 출력") { Text(output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10) }.font(Theme.font(13)).panel()
            }
        }
    }
    private func task(_ title: String, detail: String, icon: String, action: MaintenanceTask) -> some View {
        SettingsActionRow(title: title, actionTitle: title.hasPrefix("DNS") ? "초기화" : "재색인", enabled: !model.busy) { model.runMaintenance(action) }.help(detail).panel(24)
    }
}
