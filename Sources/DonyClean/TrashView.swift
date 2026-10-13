import SwiftUI
import DonyCore

struct TrashView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("휴지통").font(Theme.font(16, weight: .semibold))
                Spacer()
                Menu {
                    Button("휴지통 열기") { model.showFinder(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }
                    Button("내용 검사") { model.scanTrash() }.disabled(model.busy)
                    Divider()
                    Button("검사한 항목 영구 삭제", role: .destructive) { model.emptyInspectedTrash() }.disabled(model.busy || model.trashItems.cancelled || model.trashItems.items.isEmpty)
                } label: { Text("관리").font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.body) }
                    .menuStyle(.borderlessButton).padding(.horizontal, 12).frame(width: 128, height: 42).background(Color(hex: 0xe8ebef)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if model.trashDate != nil { Text("\(model.trashItems.items.count)개 · " + DisplayFormat.bytes(model.trashItems.totalBytes)).font(Theme.font(12)).foregroundStyle(Theme.secondary) }
            if model.trashItems.cancelled { Chip(text: "검사 중단 · 다시 검사 필요", color: Theme.amber) }
            IssuesView(issues: model.trashItems.issues)
        }.panel(24)
    }
}
