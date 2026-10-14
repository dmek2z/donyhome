import SwiftUI
import DonyCore

struct DeveloperView: View {
    @EnvironmentObject var model: AppModel
    @State private var page = 0
    @State private var selection = Set<String>()
    /// 정리할 항목 검토로 들어오면 추천 항목만 보여준다. 전체 목록은 버튼으로 연다.
    @State private var recommendedOnly = false
    private var recommendedIDs: Set<String> { Set(model.recommendedDeveloper.map(\.id)) }
    /// 추천 항목을 먼저 보여준다(안정 정렬).
    private var orderedItems: [FileCandidate] {
        let recommended = recommendedIDs
        let ordered = model.developer.items.filter { recommended.contains($0.id) } + model.developer.items.filter { !recommended.contains($0.id) }
        return recommendedOnly ? ordered.filter { recommended.contains($0.id) } : ordered
    }
    private var recommendedReason: String { "\(model.projectRetentionDays)일 이상 변경 없고 관련 도구가 종료돼 다시 만들어지는 캐시라 정리를 추천해요. 휴지통에서 복원할 수 있어요." }
    private var selected: [FileCandidate] { model.developer.items.filter { selection.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text("작업공간 · Xcode · npm · pip · Homebrew · Yarn · pnpm").font(Theme.font(14, weight: .medium)); Text((model.developer.incomplete ? "≥ " : "") + DisplayFormat.bytes(model.developer.items.reduce(0) { $0 + $1.bytes })).font(Theme.font(26, weight: .semibold)) }
                Spacer(); Button("검사") { model.scanDeveloper() }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.panel()
            if model.developer.cancelled { Chip(text: "중단됨 · 일부 결과", color: Theme.amber) }
            if model.developerDate == nil { EmptyState(icon: "gearshape", title: "개발 캐시를 검사해 주세요", subtitle: "") }
            else if model.developer.items.isEmpty { EmptyState(icon: "checkmark.circle", title: "표시할 개발 캐시가 없어요", subtitle: "") }
            else {
                if recommendedOnly {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("정리 추천 \(orderedItems.count)개 · 모두 선택됨").font(Theme.font(14, weight: .semibold))
                            Spacer()
                            DonyTextAction(title: "전체 \(model.developer.items.count)개 보기") { recommendedOnly = false; page = 0 }
                        }
                        Text(recommendedReason).font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.blueWash).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack { Text(recommendedOnly ? "추천 \(orderedItems.count)개 / 전체 \(model.developer.items.count)개" : "\(model.developer.items.count)개 항목 · 추천 \(recommendedIDs.count)개").font(Theme.font(13)); Spacer(); SelectionControl(selection: $selection, ids: model.developer.items.map(\.id), recommended: model.recommendedDeveloper.map(\.id)).disabled(model.busy || model.developer.cancelled) }
                LazyVStack(spacing: 0) {
                    ForEach(Array(orderedItems.dropFirst(page * 100).prefix(100))) { item in
                        CandidateRow(candidate: item, selection: $selection, subtitle: DeveloperCleanup.label(item) + " · " + (recommendedIDs.contains(item.id) ? "추천 · " : "추천 제외 · ") + (model.developer.decisions[item.id]?.reason ?? "직접 확인"))
                        Divider().padding(.leading, 58)
                    }
                }.panel(0)
                ListPagination(total: orderedItems.count, page: $page)
                SelectionBar(selected: selected) { model.moveToTrash(selected) }
            }
            IssuesView(issues: model.developer.issues)
        }.onAppear { if !model.reviewSelection.isEmpty { selection = Set(model.reviewSelection); model.reviewSelection = []; page = 0; recommendedOnly = true } }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll(); page = 0 }
    }
}
