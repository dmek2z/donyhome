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
                HStack { DonyIcon("clock.arrow.circlepath").foregroundStyle(Theme.primary); Text("Time Machine 로컬 스냅샷").font(Theme.font(16, weight: .semibold)); Spacer(); Button("목록 확인") { model.refreshSnapshots() }.buttonStyle(QuietButton()).disabled(model.busy) }
                if model.snapshotsDate == nil { Text("시동 디스크의 로컬 백업 시점을 확인해요.").font(Theme.font(13)).foregroundStyle(Theme.secondary) }
                else if model.localSnapshots.isEmpty { Text("로컬 스냅샷이 없어요").font(Theme.font(13)).foregroundStyle(Theme.secondary) }
                else {
                    Picker("백업 시점", selection: $selectedSnapshot) { Text("선택하세요").tag(""); ForEach(model.localSnapshots, id: \.self) { Text($0).tag($0) } }.disabled(model.busy)
                    HStack { Text("선택한 백업 시점은 영구 제거돼요.").font(Theme.font(12)).foregroundStyle(Theme.secondary); Spacer(); Button("선택한 스냅샷 제거") { model.runMaintenance(.deleteSnapshot(selectedSnapshot)) }.buttonStyle(QuietButton()).disabled(!model.localSnapshots.contains(selectedSnapshot) || model.busy) }
                }
            }.panel()
            if let output = model.maintenanceOutput {
                DisclosureGroup("작업 출력") { Text(output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10) }.font(Theme.font(13)).panel()
            }
        }
    }
    private func task(_ title: String, detail: String, icon: String, action: MaintenanceTask) -> some View {
        HStack(spacing: 14) {
            DonyIcon(icon, size: 24).foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 7) { Text(title).font(Theme.font(16, weight: .semibold)); Text(detail).font(Theme.font(12)).foregroundStyle(Theme.secondary) }
            Spacer(); Button("실행") { model.runMaintenance(action) }.buttonStyle(QuietButton()).disabled(model.busy)
        }.panel()
    }
}
