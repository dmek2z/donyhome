import SwiftUI
import DonyCore

struct TrashView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { DonyIcon("trash").foregroundStyle(Theme.primary); Text("휴지통 비우기").font(Theme.font(16, weight: .semibold)); Spacer(); Button("목록 검사") { model.scanTrash() }.buttonStyle(QuietButton()).disabled(model.busy) }
            Text(model.trashDate == nil ? "현재 사용자 휴지통을 확인해요." : "검사된 \(model.trashItems.items.count)개 · " + DisplayFormat.bytes(model.trashItems.totalBytes)).font(Theme.font(13)).foregroundStyle(Theme.secondary)
            HStack {
                Button("Finder에서 확인") { model.showFinder(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }.buttonStyle(QuietButton())
                Spacer(); Button("검사한 항목 영구 삭제") { model.emptyInspectedTrash() }.buttonStyle(QuietButton()).disabled(model.busy || model.trashItems.cancelled || model.trashItems.items.isEmpty)
            }
            if model.trashItems.cancelled { Chip(text: "중단됨 · 다시 검사 필요", color: Theme.amber) }
            IssuesView(issues: model.trashItems.issues)
        }.panel()
    }
}
