import SwiftUI
import DonyCore

struct TrashView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("휴지통").font(Theme.font(16, weight: .semibold))
                Spacer()
                DonyMenuButton(title: "관리") {
                    Button("휴지통 열기") { model.showFinder(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }
                    Button("내용 검사") { model.scanTrash() }.disabled(model.busy)
                    Divider()
                    Button("검사한 항목 영구 삭제", role: .destructive) { model.emptyInspectedTrash() }.disabled(model.busy || model.trashItems.cancelled || model.trashItems.items.isEmpty)
                }
            }
            if model.trashDate != nil { Text("\(model.trashItems.items.count)개 · " + DisplayFormat.bytes(model.trashItems.totalBytes)).font(Theme.font(12)).foregroundStyle(Theme.secondary) }
            if model.trashItems.cancelled { Chip(text: "검사 중단 · 다시 검사 필요", color: Theme.amber) }
            IssuesView(issues: model.trashItems.issues)
        }.panel(24)
    }
}
