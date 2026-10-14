import SwiftUI
import DonyCore

struct ToolCareView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    private var tools: [AITool] { AITool.allCases.filter { model.connectedTools.contains($0) } }
    private var focus: AITool? { model.developmentToolFilter }
    private var items: [ToolStorageItem] { model.toolStorage.items.filter { focus == nil || $0.owners.contains(focus!) } }
    private var eligible: [ToolStorageItem] { items.filter(\.isEligible) }
    private var memoryBytes: Int64 { model.aiUsage.filter { focus == nil || $0.tool == focus }.reduce(0) { $0 + $1.bytes } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Text("도구가 쓰는 공간·메모리").font(Theme.font(17, weight: .semibold))
                Spacer()
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
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                metric("캐시·로그", value: model.toolStorageDate == nil ? "검사 전" : DisplayFormat.bytes(items.reduce(0) { $0 + $1.candidate.bytes }))
                metric("정리 가능한 파일", value: model.toolStorageCurrent ? DisplayFormat.bytes(eligible.reduce(0) { $0 + $1.candidate.bytes }) : "다시 검사")
                metric("실행 중 메모리", value: DisplayFormat.bytes(memoryBytes))
            }
            HStack {
                DonyMenuButton(title: focus?.title ?? "모든 도구", width: Theme.filterWidth) {
                    Button("모든 도구") { model.developmentToolFilter = nil }
                    ForEach(tools) { tool in Button(tool.title) { model.developmentToolFilter = tool } }
                }.disabled(model.busy)
                DonyMenuButton(title: "\(model.projectRetentionDays)일 보관") {
                    ForEach([1, 3, 7, 14, 30, 90], id: \.self) { days in
                        Button("\(days)일") { model.projectRetentionDays = days }
                    }
                }.disabled(model.busy)
                Spacer()
                DonyMenuButton(title: "자원 관리") {
                    Button("CLI 작업 확인") { model.reviewDevelopmentTasks(focus) }
                    Button("앱 메모리·종료 확인") { model.reviewToolMemory(focus) }
                    Button("프로젝트 생성물 확인") { model.developmentMode = "프로젝트" }
                    Button("연동 설정") { model.developmentMode = "연동" }
                }.disabled(model.busy)
            }
            Text("메모리는 프로세스 합산값으로 공유 영역이 중복될 수 있어요. 파일 정리와 작업 일시 정지는 RAM 확보로 계산하지 않아요.")
                .font(Theme.font(11)).foregroundStyle(Theme.secondary)
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
                SelectionControl(selection: $selection, ids: eligible.map(\.id)).disabled(model.busy || !model.toolStorageCurrent)
            }
            Text("\(model.projectRetentionDays)일 이상 지난 파일만 선택할 수 있어요. 사용 중인 도구는 제외해요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            if model.toolStorage.cancelled { Text("검사 중단 · 다시 검사해 주세요").font(Theme.font(12)).foregroundStyle(Theme.amber) }
            else if items.isEmpty {
                Text(model.toolStorageDate == nil ? "도구 검사로 캐시·로그 경로를 확인해 주세요." : "확인된 정리 대상이 없어요. 경로 미확인 도구는 프로젝트 폴더를 연결해 생성물을 확인할 수 있어요.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
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
                if items.count > 100 { Text("상위 100개 표시 · 전체 선택에는 모든 정리 가능 항목이 포함돼요.").font(Theme.font(11)).foregroundStyle(Theme.secondary) }
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
