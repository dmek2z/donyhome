import SwiftUI
import DonyCore

struct CacheCleanupView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    @State private var filter = "전체"
    private var visible: [FileCandidate] { model.cleanup.items.filter { filter == "전체" || ($0.kind == .cache ? "캐시" : "로그") == filter } }
    private var selected: [FileCandidate] { model.cleanup.items.filter { selection.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.cleanupDate == nil ? "정리 후보를 찾아볼까요?" : DisplayFormat.bytes(model.cleanup.totalBytes)).font(Theme.font(26, weight: .semibold))
                    Text(model.cleanupDate == nil ? "검사는 파일을 변경하지 않아요." : "검사된 \(model.cleanup.items.count)개 항목의 크기").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                }
                Spacer(); Button { model.scanCleanup() } label: { DonyLabel("캐시 · 로그 검사", icon: "magnifyingglass") }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.panel()
            if model.cleanup.cancelled { Chip(text: "중단됨 · 일부 결과", color: Theme.amber) }
            if model.cleanupDate == nil {
                EmptyState(icon: "sparkles", title: "캐시 · 로그를 검사해 주세요", subtitle: "")
            } else if model.cleanup.items.isEmpty {
                EmptyState(icon: "checkmark.circle", title: "표시할 정리 후보가 없어요", subtitle: model.cleanup.issues.isEmpty ? "현재 검사 범위에서 정리할 항목을 찾지 못했습니다." : "확인하지 못한 경로가 있습니다. 아래 건너뛴 항목도 확인해 주세요.")
            } else {
                HStack {
                    DonyTabs(options: ["전체", "캐시", "로그"], selection: $filter)
                    Spacer(); Button("추천 항목 선택") { selection = Set(model.recommendedCleanup.map(\.id)) }.buttonStyle(QuietButton()).disabled(model.busy || model.cleanup.cancelled)
                    Button("선택 해제") { selection.removeAll() }.buttonStyle(.plain).font(Theme.font(11)).foregroundStyle(Theme.secondary)
                }
                LazyVStack(spacing: 0) {
                    ForEach(visible) { candidate in
                        CandidateRow(candidate: candidate, selection: $selection, subtitle: model.cleanupDecisions[candidate.id].map { ($0.isRecommended ? "추천 · " : "") + $0.reason })
                        if candidate.id != visible.last?.id { Divider().padding(.leading, 58) }
                    }
                }.panel(0)
                SelectionBar(selected: selected) { model.moveToTrash(selected) }
            }
            IssuesView(issues: model.cleanup.issues)
        }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll() }.onChange(of: filter) { _, _ in selection.removeAll() }
    }
}

struct CleanupView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "저장 공간 정리")
            DonyTabs(options: ["캐시 · 로그", "개발 캐시"], selection: $model.cleanupMode)
            if model.cleanupMode == "개발 캐시" { DeveloperView() } else { CacheCleanupView() }
        }
    }
}
