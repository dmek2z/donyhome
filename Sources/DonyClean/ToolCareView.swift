import SwiftUI
import DonyCore

struct ToolCareView: View {
    @EnvironmentObject var model: AppModel
    @State private var page = 0
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
                DonyTextAction(title: "정리 기준") { showSettings = true }.disabled(model.busy)
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
        .onChange(of: model.toolStorageDate) { _, _ in selection.removeAll(); page = 0 }
        .onChange(of: model.developmentToolFilter) { _, _ in selection.removeAll(); page = 0 }
        .onChange(of: model.connectedTools) { _, _ in
            selection.removeAll()
            if let focus, !model.connectedTools.contains(focus) { model.developmentToolFilter = nil }
        }
        .onChange(of: model.projectRetentionDays) { _, _ in selection.removeAll(); page = 0 }
        .sheet(isPresented: $showSettings) { RetentionSettingsSheet() }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                metric("확인된 캐시·로그", value: model.toolStorageDate == nil ? "검사 전" : (model.toolStorage.incompleteTools.isEmpty ? "" : "≥ ") + DisplayFormat.bytes(items.reduce(0) { $0 + $1.candidate.bytes }))
                metric("정리 가능한 파일", value: model.toolStorageCurrent ? DisplayFormat.bytes(eligible.reduce(0) { $0 + $1.candidate.bytes }) : "다시 검사")
                metric("정리 제외", value: DisplayFormat.bytes(items.filter { !$0.isEligible }.reduce(0) { $0 + $1.candidate.bytes }))
                metric("실행 중 메모리", value: DisplayFormat.bytes(memoryBytes))
                    .help("프로세스 합산값 · 공유 영역이 중복될 수 있어요. 파일 정리와 일시 정지는 RAM을 비우지 않아요.")
            }
            HStack {
                if let focus {
                    ToolIcon(tool: focus, size: 22)
                    Text(focus.title).font(Theme.font(13, weight: .semibold))
                    DonyTextAction(title: "전체 보기") { model.developmentToolFilter = nil }
                }
                Spacer()
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
                ToolIcon(tool: tool, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.title).font(Theme.font(14, weight: .semibold)).lineLimit(1)
                    Text(usage.map { "실행 중 · \($0.processes.count)개 프로세스" } ?? model.toolStatuses[tool] ?? "연동 확인 필요")
                        .font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(model.toolStorageDate == nil ? "—" : model.toolStorage.recognizedTools.contains(tool) ? (model.toolStorage.incompleteTools.contains(tool) ? "≥ " : "") + DisplayFormat.bytes(files.reduce(0) { $0 + $1.candidate.bytes }) : "경로 미확인").frame(width: 85, alignment: .trailing)
                Text(model.toolStorageCurrent ? DisplayFormat.bytes(files.filter(\.isEligible).reduce(0) { $0 + $1.candidate.bytes }) : "—").frame(width: 85, alignment: .trailing)
                Text(usage.map { DisplayFormat.bytes($0.bytes) } ?? "—").frame(width: 85, alignment: .trailing)
                Text(cpu.isEmpty ? "—" : DisplayFormat.percent(cpu.reduce(0, +))).frame(width: 60, alignment: .trailing)
            }.font(Theme.font(12)).monospacedDigit().foregroundStyle(Theme.body)
                .padding(.horizontal, 20).frame(height: Theme.listRowHeight)
                .background(focus == tool ? Theme.primary.opacity(0.06) : Color.clear).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("도구 상세 " + tool.title)
    }
    private var selectedBytes: Int64 { items.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.candidate.bytes } }
    /// 정리할 수 없는 이유를 정리 기준과 연결해서 묶어 보여준다.
    private func policyLabel(_ reason: String) -> String {
        if reason.hasPrefix("최근 변경") { return "\(model.projectRetentionDays)일 안에 쓴 파일(정리 기준)" }
        if reason.hasPrefix("사용 중인 도구") { return "실행 중인 도구의 파일" }
        if reason.hasPrefix("열린 파일 ·") { return "다른 프로그램이 열어 둔 파일" }
        return "상태를 확인하지 못한 파일"
    }
    private var blockedSummary: String {
        var counts: [String: Int] = [:]
        for item in items where !item.isEligible { counts[policyLabel(item.reason), default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \($0.value)개" }.joined(separator: " · ")
    }
    private var cleanBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.isEmpty ? (eligible.isEmpty ? "지금 정리할 수 있는 파일이 없어요" : "정리할 파일을 선택해 주세요") : "\(selection.count)개 선택 · " + DisplayFormat.bytes(selectedBytes)).font(Theme.font(15, weight: .semibold))
                    Text(eligible.isEmpty ? "정리 기준(\(model.projectRetentionDays)일 이상 안 쓴 항목)에 맞지 않거나 보호 중인 파일이에요." : "정리 가능 \(eligible.count)개 · 선택한 파일은 휴지통으로 이동해요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 12)
                Button("선택한 파일 정리") { model.cleanToolStorage(selection) }.buttonStyle(PrimaryButton()).disabled(model.busy || !model.toolStorageCurrent || selection.isEmpty)
            }
            if eligible.isEmpty, !blockedSummary.isEmpty { Text(blockedSummary).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.body) }
            if !model.cleanRunningToolFiles, items.contains(where: { $0.reason.hasPrefix("사용 중인 도구") }) {
                Text("실행 중인 도구의 캐시는 기본으로 정리하지 않아요. 정리 기준에서 켤 수 있어요.").font(Theme.font(12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private var filePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if let focus { ToolIcon(tool: focus, size: 26) }
                Text((focus?.title ?? "전체 도구") + " · 정리 대상").font(Theme.font(17, weight: .semibold))
                Spacer()
                if !eligible.isEmpty {
                    SelectionControl(selection: $selection, ids: eligible.map(\.id)).disabled(model.busy || !model.toolStorageCurrent)
                }
            }
            if model.toolStorageDate != nil, !model.toolStorage.cancelled, !items.isEmpty { cleanBar }
            if model.toolStorage.cancelled { Text("검사 중단 · 다시 검사해 주세요").font(Theme.font(12)).foregroundStyle(Theme.amber) }
            else if items.isEmpty {
                Text(model.toolStorageDate == nil ? "검사 전" : "정리 대상 없음").font(Theme.font(13)).foregroundStyle(Theme.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.dropFirst(page * 100).prefix(100))) { item in
                        HStack(spacing: 12) {
                            Toggle("선택 " + item.candidate.name, isOn: Binding(get: { selection.contains(item.id) }, set: { if $0 { selection.insert(item.id) } else { selection.remove(item.id) } }))
                                .toggleStyle(DonyCheckbox()).labelsHidden().disabled(model.busy || !model.toolStorageCurrent || !item.isEligible)
                            if let owner = item.owners.sorted(by: { $0.title < $1.title }).first { ToolIcon(tool: owner, size: 24).help(item.owners.map(\.title).sorted().joined(separator: " · ")) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.candidate.name).font(Theme.font(13, weight: .medium)).lineLimit(1).help(item.id)
                                Text(item.owners.map(\.title).sorted().joined(separator: " · ") + " · " + item.reason).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }; Spacer()
                            Text(DisplayFormat.bytes(item.candidate.bytes)).font(Theme.font(12)).monospacedDigit()
                        }.frame(height: Theme.listRowHeight)
                        Divider()
                    }
                }
                ListPagination(total: items.count, page: $page)
            }
        }.panel()
    }
}
