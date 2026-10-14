import SwiftUI
import DonyCore

struct DeveloperView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    private var selected: [FileCandidate] { model.developer.items.filter { selection.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text("Xcode · npm · pip · Homebrew · Yarn").font(Theme.font(14, weight: .medium)); Text(DisplayFormat.bytes(model.developer.items.reduce(0) { $0 + $1.bytes })).font(Theme.font(26, weight: .semibold)) }
                Spacer(); Button("검사") { model.scanDeveloper() }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.panel()
            if model.developer.cancelled { Chip(text: "중단됨 · 일부 결과", color: Theme.amber) }
            if model.developerDate == nil { EmptyState(icon: "gearshape", title: "개발 캐시를 검사해 주세요", subtitle: "") }
            else if model.developer.items.isEmpty { EmptyState(icon: "checkmark.circle", title: "표시할 개발 캐시가 없어요", subtitle: "") }
            else {
                HStack { Text("\(model.developer.items.count)개 항목").font(Theme.font(13)); Spacer(); SelectionControl(selection: $selection, ids: model.developer.items.map(\.id), recommended: model.recommendedDeveloper.map(\.id)).disabled(model.busy || model.developer.cancelled) }
                LazyVStack(spacing: 0) {
                    ForEach(model.developer.items) { item in
                        CandidateRow(candidate: item, selection: $selection, subtitle: DeveloperCleanup.label(item) + " · " + (model.developer.decisions[item.id]?.reason ?? "직접 확인"))
                        Divider().padding(.leading, 58)
                    }
                }.panel(0)
                SelectionBar(selected: selected) { model.moveToTrash(selected) }
            }
            IssuesView(issues: model.developer.issues)
        }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll() }
    }
}
