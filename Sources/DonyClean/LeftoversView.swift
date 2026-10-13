import SwiftUI
import DonyCore

struct LeftoversView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    private var selected: [FileCandidate] { model.leftovers.items.filter { selection.contains($0.id) }.map(\.candidate) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text("제거된 앱의 잔여물 후보").font(Theme.font(16, weight: .semibold)); Text("\(model.leftovers.items.count)개 · " + DisplayFormat.bytes(model.leftovers.items.reduce(0) { $0 + $1.candidate.bytes })).font(Theme.font(13)).foregroundStyle(Theme.secondary) }
                Spacer(); Button("잔여물 검사") { model.scanLeftovers() }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.panel()
            Text("설치·등록된 앱을 찾지 못한 ID예요. 도우미나 다른 위치의 앱일 수 있고 설정·사용자 데이터가 포함돼요. 삭제할 앱의 흔적인지 직접 확인해 주세요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            if model.leftovers.cancelled { Chip(text: "중단됨 · 일부 결과", color: Theme.amber) }
            if model.leftoverDate == nil { EmptyState(icon: "square.stack.3d.up", title: "잔여물 후보를 검사해 주세요", subtitle: "") }
            else if model.leftovers.items.isEmpty { EmptyState(icon: "checkmark.circle", title: "표시할 잔여물 후보가 없어요", subtitle: "") }
            else {
                LazyVStack(spacing: 0) { ForEach(model.leftovers.items) { item in CandidateRow(candidate: item.candidate, selection: $selection, subtitle: item.bundleID + " · " + item.candidate.root.lastPathComponent); Divider().padding(.leading, 58) } }.panel(0)
                SelectionBar(selected: selected) { model.moveToTrash(selected) }
            }
            IssuesView(issues: model.leftovers.issues)
        }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll() }
    }
}
