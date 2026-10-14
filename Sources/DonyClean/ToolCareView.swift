import SwiftUI
import DonyCore

struct ToolCareView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    @State private var showSettings = false
    private var tools: [AITool] { AITool.allCases.filter { model.connectedTools.contains($0) } }
    private var focus: AITool? { model.developmentToolFilter }
    private var items: [ToolStorageItem] { model.toolStorage.items.filter { focus == nil || $0.owners.contains(focus!) } }
    private var eligible: [ToolStorageItem] { items.filter(\.isEligible) }
    private var memoryBytes: Int64 { model.aiUsage.filter { focus == nil || $0.tool == focus }.reduce(0) { $0 + $1.bytes } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Text("도구별 사용량").font(Theme.font(17, weight: .semibold))
                Spacer()
                DonyTextAction(title: "보관 설정") { showSettings = true }.disabled(model.busy)
                Button("도구 검사") { model.scanToolStorage() }.buttonStyle(PrimaryButton()).disabled(model.busy || tools.isEmpty)
            }
            if tools.isEmpty {
                EmptyState(icon: "terminal", title: "개발 도구를 연결해 주세요", subtitle: "")
                SettingsActionRow(title: "사용하는 도구 선택", actionTitle: "연동 설정") { model.developmentMode = "연동" }.panel()
            } else {
                summary
                if model.developmentPressureReview {
                    SettingsActionRow(title: "메모리가 바빠요 · 사용 중인 작업을 확인해 주세요", actionTitle: "작업 확인") { model.reviewDevelopmentTasks() }.panel()
                }
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("도구"); Spacer()
                        Text("캐시·로그").frame(width: 85, alignment: .trailing)
                        Text("정리 가능").frame(width: 85, alignment: .trailing)
                        Text("메모리").frame(width: 85, alignment: .trailing)
                        Text("CPU").frame(width: 60, alignment: .trailing)
                    }.font(Theme.font(11)).foregroundStyle(Theme.secondary).padding(.horizontal, 20).padding(.vertical, 12)
                    ForEach(tools) { tool in
                        toolRow(tool)
                        if tool != tools.last { Divider().padding(.leading, 20) }
                    }
                }.panel(0)
                filePanel
            }
            IssuesView(issues: model.toolStorage.issues)
        }
        .onChange(of: model.toolStorageDate) { _, _ in selection.removeAll() }
        .onChange(of: model.developmentToolFilter) { _, _ in selection.removeAll() }
        .onChange(of: model.connectedTools) { _, _ in
            selection.removeAll()
            if let focus, !model.connectedTools.contains(focus) { model.developmentToolFilter = nil }
        }
        .onChange(of: model.projectRetentionDays) { _, _ in selection.removeAll() }
        .sheet(isPresented: $showSettings) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("캐시·로그 보관").font(Theme.font(20, weight: .semibold))
                    Spacer()
                    DonyTextAction(title: "완료") { showSettings = false }
                }
                DonyChoices(options: ["1일", "3일", "7일", "14일", "30일", "90일"], selection: Binding(
                    get: { "\(model.projectRetentionDays)일" },
                    set: { model.projectRetentionDays = Int($0.dropLast()) ?? 14 }
                )).disabled(model.busy)
            }.padding(24).frame(width: 520).background(Theme.canvas)
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                metric("캐시·로그", value: model.toolStorageDate == nil ? "검사 전" : DisplayFormat.bytes(items.reduce(0) { $0 + $1.candidate.bytes }))
                metric("정리 가능한 파일", value: model.toolStorageCurrent ? DisplayFormat.bytes(eligible.reduce(0) { $0 + $1.candidate.bytes }) : "다시 검사")
                metric("실행 중 메모리", value: DisplayFormat.bytes(memoryBytes))
                    .help("프로세스 합산값 · 공유 영역이 중복될 수 있어요. 파일 정리와 일시 정지는 RAM을 비우지 않아요.")
            }
            HStack {
                if let focus {
                    Text(focus.title).font(Theme.font(13, weight: .semibold))
                    DonyTextAction(title: "전체 보기") { model.developmentToolFilter = nil }
                }
                Spacer()
                Button { model.reviewDevelopmentTasks(focus) } label: {
                    Text("작업 확인").frame(width: Theme.actionWidth - 24)
                }.buttonStyle(QuietButton()).disabled(model.busy)
                Button { model.reviewToolMemory(focus) } label: {
                    Text("메모리 확인").frame(width: Theme.actionWidth - 24)
                }.buttonStyle(QuietButton()).disabled(model.busy)
            }
        }.panel()
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(12)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.font(21, weight: .semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func toolRow(_ tool: AITool) -> some View {
        let files = model.toolStorage.items.filter { $0.owners.contains(tool) }
        let usage = model.aiUsage.first { $0.tool == tool }
        let cpu = usage?.processes.compactMap(\.cpuPercent) ?? []
        return Button { model.developmentToolFilter = tool } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.title).font(Theme.font(14, weight: .semibold)).lineLimit(1)
                    Text(usage.map { "실행 중 · \($0.processes.count)개 프로세스" } ?? model.toolStatuses[tool] ?? "연동 확인 필요")
                        .font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(model.toolStorageDate == nil ? "—" : model.toolStorage.recognizedTools.contains(tool) ? DisplayFormat.bytes(files.reduce(0) { $0 + $1.candidate.bytes }) : "경로 미확인").frame(width: 85, alignment: .trailing)
                Text(model.toolStorageCurrent ? DisplayFormat.bytes(files.filter(\.isEligible).reduce(0) { $0 + $1.candidate.bytes }) : "—").frame(width: 85, alignment: .trailing)
                Text(usage.map { DisplayFormat.bytes($0.bytes) } ?? "—").frame(width: 85, alignment: .trailing)
                Text(cpu.isEmpty ? "—" : DisplayFormat.percent(cpu.reduce(0, +))).frame(width: 60, alignment: .trailing)
            }.font(Theme.font(12)).monospacedDigit().foregroundStyle(Theme.body)
                .padding(.horizontal, 20).frame(height: Theme.listRowHeight)
                .background(focus == tool ? Theme.primary.opacity(0.06) : Color.clear).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("도구 상세 " + tool.title)
    }
    private var filePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text((focus?.title ?? "전체 도구") + " · 정리 대상").font(Theme.font(17, weight: .semibold))
                Spacer()
                if !eligible.isEmpty {
                    SelectionControl(selection: $selection, ids: eligible.map(\.id)).disabled(model.busy || !model.toolStorageCurrent)
                }
            }
            if model.toolStorage.cancelled { Text("검사 중단 · 다시 검사해 주세요").font(Theme.font(12)).foregroundStyle(Theme.amber) }
            else if items.isEmpty {
                Text(model.toolStorageDate == nil ? "검사 전" : "정리 대상 없음").font(Theme.font(13)).foregroundStyle(Theme.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(100))) { item in
                        HStack(spacing: 12) {
                            Toggle("선택 " + item.candidate.name, isOn: Binding(get: { selection.contains(item.id) }, set: { if $0 { selection.insert(item.id) } else { selection.remove(item.id) } }))
                                .toggleStyle(DonyCheckbox()).labelsHidden().disabled(model.busy || !model.toolStorageCurrent || !item.isEligible)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.candidate.name).font(Theme.font(13, weight: .medium)).lineLimit(1).help(item.id)
                                Text(item.owners.map(\.title).sorted().joined(separator: " · ") + " · " + item.reason).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }; Spacer()
                            Text(DisplayFormat.bytes(item.candidate.bytes)).font(Theme.font(12)).monospacedDigit()
                        }.frame(height: Theme.listRowHeight)
                        Divider()
                    }
                }
                if items.count > 100 { Text("100 / \(items.count)개 표시").font(Theme.font(11)).foregroundStyle(Theme.secondary).help("전체 선택은 표시되지 않은 정리 가능 항목도 포함해요.") }
            }
            if !selection.isEmpty {
                HStack {
                    Text("\(selection.count)개 선택").font(Theme.font(13))
                    Spacer()
                    Button("선택한 파일 정리") { model.cleanToolStorage(selection) }.buttonStyle(PrimaryButton()).disabled(model.busy || !model.toolStorageCurrent)
                }
            }
        }.panel()
    }
}
