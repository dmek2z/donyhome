import SwiftUI
import DonyCore

struct LeftoversView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    private var selected: [FileCandidate] { model.leftovers.items.filter { selection.contains($0.id) }.map(\.candidate) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text("남은 앱 파일").font(Theme.font(16, weight: .semibold)); Text("\(model.leftovers.items.count)개 · " + DisplayFormat.bytes(model.leftovers.items.reduce(0) { $0 + $1.candidate.bytes })).font(Theme.font(13)).foregroundStyle(Theme.secondary) }
                Spacer(); Button("남은 파일 검사") { model.scanLeftovers() }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.panel()
            Text("연결된 앱을 찾지 못한 파일입니다. 설정·사용자 데이터가 포함될 수 있어요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            if model.leftovers.cancelled { Chip(text: "중단됨 · 일부 결과", color: Theme.amber) }
            if model.leftoverDate == nil { EmptyState(icon: "square.stack.3d.up", title: "남은 앱 파일을 검사해 주세요", subtitle: "") }
            else if model.leftovers.items.isEmpty { EmptyState(icon: "checkmark.circle", title: "표시할 남은 앱 파일가 없어요", subtitle: "") }
            else {
                HStack { Spacer(); SelectionControl(selection: $selection, ids: model.leftovers.items.map { $0.candidate.id }).disabled(model.busy) }
                LazyVStack(spacing: 0) { ForEach(model.leftovers.items) { item in CandidateRow(candidate: item.candidate, selection: $selection, subtitle: item.bundleID + " · " + item.candidate.root.lastPathComponent); Divider().padding(.leading, 58) } }.panel(0)
                SelectionBar(selected: selected) { model.moveToTrash(selected) }
            }
            IssuesView(issues: model.leftovers.issues)
        }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll() }
    }
}
