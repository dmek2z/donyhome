import SwiftUI
import DonyCore

struct DeveloperView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    private var selected: [FileCandidate] { model.developer.items.filter { selection.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text("방치된 작업공간 · Xcode · npm · pip · Homebrew · Yarn").font(Theme.font(14, weight: .medium)); Text(DisplayFormat.bytes(model.developer.items.reduce(0) { $0 + $1.bytes })).font(Theme.font(26, weight: .semibold)) }
                Spacer(); Button("개발 캐시 검사") { model.scanDeveloper() }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.panel()
            if model.developer.cancelled { Chip(text: "중단됨 · 일부 결과", color: Theme.amber) }
            if model.developerDate == nil { EmptyState(icon: "gearshape", title: "개발 캐시를 검사해 주세요", subtitle: "") }
            else if model.developer.items.isEmpty { EmptyState(icon: "checkmark.circle", title: "표시할 개발 캐시가 없어요", subtitle: "") }
            else {
                HStack { Text("\(model.developer.items.count)개 생성물 · 추천 \(model.recommendedDeveloper.count)개").font(Theme.font(13)); Spacer(); Button("추천 항목 선택") { selection = Set(model.recommendedDeveloper.map(\.id)) }.buttonStyle(QuietButton()).disabled(model.busy || model.developer.cancelled) }
                LazyVStack(spacing: 0) {
                    ForEach(model.developer.items) { item in
                        CandidateRow(candidate: item, selection: $selection, subtitle: DeveloperCleanup.label(item) + " · " + (model.developer.decisions[item.id]?.reason ?? "직접 확인"))
                        Divider().padding(.leading, 58)
                    }
                }.panel(0)
                SelectionBar(selected: selected) { model.moveToTrash(selected) }
            }
            Text("방치된 작업공간은 변경·미푸시 커밋이 없고 14일 이상 쓰지 않은 것만 추천하며, 휴지통에서 복원할 수 있어요. Xcode Archives와 프로젝트 원본은 유지해요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            IssuesView(issues: model.developer.issues)
        }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll() }
    }
}
