import SwiftUI
import DonyCore

struct CacheCleanupView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    @State private var filter = "전체"
    @State private var focus: String?
    @State private var showSettings = false
    private var groups: [CacheInventoryGroup] { model.cleanupInventory.filter { filter == "전체" || ($0.kind == .cache ? "캐시" : "로그") == filter } }
    private var visible: [FileCandidate] { model.cleanup.items.filter { item in
        (filter == "전체" || (item.kind == .cache ? "캐시" : "로그") == filter) && (focus == nil || item.id == focus || item.id.hasPrefix(focus! + "/"))
    } }
    private var selected: [FileCandidate] { visible.filter { selection.contains($0.id) } }
    private var measured: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    private var recommended: Int64 { groups.reduce(0) { $0 + $1.recommendedBytes } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("캐시·로그").font(Theme.font(17, weight: .semibold))
                Spacer()
                DonyTextAction(title: "보관 설정") { showSettings = true }.disabled(model.busy)
                Button("검사") { model.scanCleanup() }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }
            if model.cleanupDate == nil {
                EmptyState(icon: "sparkles", title: "캐시·로그를 검사해 주세요", subtitle: "")
            } else {
                HStack(spacing: 20) {
                    metric("발견", value: (groups.contains { $0.incomplete } ? "≥ " : "") + DisplayFormat.bytes(measured))
                    metric("추천", value: DisplayFormat.bytes(recommended))
                    metric("보관", value: DisplayFormat.bytes(max(0, measured - recommended)))
                }.panel()
                if model.cleanup.cancelled { Chip(text: "중단됨 · 일부 결과", color: Theme.amber) }
                DonyTabs(options: ["전체", "캐시", "로그"], selection: $filter)
                if groups.isEmpty {
                    EmptyState(icon: "checkmark.circle", title: "확인된 항목 없음", subtitle: "")
                } else {
                    LazyVStack(spacing: 0) {
                        HStack { Text("앱·경로"); Spacer(); Text("발견").frame(width: 100, alignment: .trailing); Text("추천").frame(width: 100, alignment: .trailing); Text("보관").frame(width: 100, alignment: .trailing) }
                            .font(Theme.font(11)).foregroundStyle(Theme.secondary).padding(.horizontal, 20).padding(.vertical, 12)
                        ForEach(groups) { group in
                            Button { focus = focus == group.id ? nil : group.id; selection.removeAll() } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.title).font(Theme.font(14, weight: .semibold)).lineLimit(1)
                                        Text(group.incomplete ? "일부 결과 · 확인 필요" : group.status).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text((group.incomplete ? "≥ " : "") + DisplayFormat.bytes(group.bytes)).frame(width: 100, alignment: .trailing)
                                    Text(DisplayFormat.bytes(group.recommendedBytes)).frame(width: 100, alignment: .trailing)
                                    Text(DisplayFormat.bytes(group.protectedBytes)).frame(width: 100, alignment: .trailing)
                                }.font(Theme.font(12)).monospacedDigit().foregroundStyle(Theme.body)
                                    .padding(.horizontal, 20).frame(height: Theme.listRowHeight)
                                    .background(focus == group.id ? Theme.blueWash : Color.clear).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(group.id).accessibilityLabel("캐시 상세 " + group.title)
                            if group.id != groups.last?.id { Divider().padding(.leading, 20) }
                        }
                    }.panel(0)
                }
                if !visible.isEmpty {
                    HStack {
                        Text(focus.map { URL(fileURLWithPath: $0).lastPathComponent + " · 추천 파일" } ?? "추천 파일").font(Theme.font(17, weight: .semibold))
                        Text("\(visible.count)개").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        if focus != nil { DonyTextAction(title: "전체 보기") { focus = nil; selection.removeAll() } }
                        Spacer()
                        SelectionControl(selection: $selection, ids: visible.map(\.id)).disabled(model.busy || model.cleanup.cancelled)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visible.prefix(100))) { item in
                            CandidateRow(candidate: item, selection: $selection, subtitle: model.cleanupDecisions[item.id]?.reason)
                            Divider().padding(.leading, 58)
                        }
                    }.panel(0)
                    if visible.count > 100 { Text("100 / \(visible.count)개 표시").font(Theme.font(11)).foregroundStyle(Theme.secondary).help("전체 선택은 모든 추천 파일을 포함해요.") }
                    SelectionBar(selected: selected) { model.moveToTrash(selected, recommendedOnly: true) }
                } else if focus != nil {
                    HStack { Text("추천 파일 없음").font(Theme.font(13)).foregroundStyle(Theme.secondary); Spacer(); DonyTextAction(title: "전체 보기") { focus = nil } }.panel()
                }
            }
            IssuesView(issues: model.cleanup.issues)
        }.onChange(of: model.cleanupDate) { _, _ in selection.removeAll(); focus = nil }
            .onChange(of: filter) { _, _ in selection.removeAll(); focus = nil }
            .sheet(isPresented: $showSettings) { RetentionSettingsSheet() }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(12)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.font(21, weight: .semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CleanupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "캐시·로그 정리")
            CacheCleanupView()
        }
    }
}
