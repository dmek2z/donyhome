import SwiftUI
import AppKit
import DonyCore

private struct UsageRow: Identifiable {
    var id: String { process.id }
    let process: ProcessReading
    let name: String
    let cpu: Double?
    let memory: Int64
    let count: Int
    let icon: NSImage?
}

struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    @State private var scope = "내 앱"
    @State private var memorySort = true
    @State private var search = ""
    @State private var toolFilter: AITool?
    @State private var selection = Set<String>()
    private var displayedRows: [UsageRow] { Array(rows.prefix(100)) }
    private var selectableRows: [UsageRow] { displayedRows.filter { model.canQuit($0.process) } }
    private var selectedRows: [UsageRow] { rows.filter { selection.contains($0.id) && model.canQuit($0.process) } }
    private var rows: [UsageRow] {
        let processes = model.snapshot.processes
        var output: [UsageRow] = []
        if scope == "내 앱" {
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
                guard let parent = processes.first(where: { $0.pid == app.processIdentifier && $0.uid == getuid() }) else { continue }
                let base = app.bundleURL?.path
                let family = processes.filter { row in
                    row.uid == parent.uid && (row.pid == parent.pid || base.map { row.path.hasPrefix($0 + "/") } == true)
                }
                let measured = family.compactMap(\.cpuPercent)
                output.append(UsageRow(process: parent, name: app.localizedName ?? parent.name, cpu: measured.isEmpty ? nil : measured.reduce(0, +), memory: family.filter { $0.memoryBytes >= 0 }.reduce(0) { $0 + $1.memoryBytes }, count: family.count, icon: app.icon))
            }
        } else {
            output = processes.filter { scope == "전체 프로세스" || $0.uid == getuid() }.map {
                UsageRow(process: $0, name: $0.name, cpu: $0.cpuPercent, memory: $0.memoryBytes, count: 1, icon: NSRunningApplication(processIdentifier: $0.pid)?.icon)
            }
        }
        output = output.filter {
            DevelopmentResourceFilter.includes($0.process, tool: toolFilter, applicationTools: model.aiApplicationTools) &&
                (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.process.pid).contains(search))
        }
        return output.sorted {
            let a = memorySort ? Double($0.memory) : ($0.cpu ?? -1)
            let b = memorySort ? Double($1.memory) : ($1.cpu ?? -1)
            return a == b ? $0.name < $1.name : a > b
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "CPU · 메모리")
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("CPU").font(Theme.font(13, weight: .medium)); Spacer(); Text(DisplayFormat.percent(model.snapshot.cpuPercent)).font(Theme.font(24, weight: .semibold)).monospacedDigit() }
                    Sparkline(values: model.cpuHistory, title: "CPU")
                }.frame(maxWidth: .infinity).frame(height: 104, alignment: .top).panel(20)
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("메모리").font(Theme.font(13, weight: .medium)); Spacer(); Chip(text: model.snapshot.pressure.label, color: model.pressureColor) }
                    Text((model.snapshot.memoryUsed.map(DisplayFormat.bytes) ?? "—") + " / " + DisplayFormat.bytes(model.snapshot.memoryTotal)).font(Theme.font(21, weight: .semibold)).monospacedDigit()
                    Sparkline(values: model.memoryHistory, color: model.pressureColor, title: "메모리 사용량")
                }.frame(maxWidth: .infinity).frame(height: 104, alignment: .top).panel(20)
            }
            if let relief = model.lastRelief {
                VStack(alignment: .leading, spacing: 9) {
                    Text(relief.app + " 종료 요청 후 관측").font(Theme.font(13, weight: .semibold))
                    HStack(spacing: 30) {
                        Text("CPU  " + DisplayFormat.percent(relief.before.cpuPercent) + " → " + DisplayFormat.percent(relief.after.cpuPercent))
                        Text("메모리  " + (relief.before.memoryUsed.map(DisplayFormat.bytes) ?? "—") + " → " + (relief.after.memoryUsed.map(DisplayFormat.bytes) ?? "—"))
                    }.font(Theme.font(12, weight: .medium)).monospacedDigit()
                    Text("전체 시스템 · 요청 3초 후").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                }.panel(16)
            }
            HStack(spacing: 12) {
                DonyMenuButton(title: toolFilter?.title ?? (scope == "내 앱" ? "실행 중인 앱" : scope), width: Theme.filterWidth) {
                    Button("실행 중인 앱 · 필터 해제") { scope = "내 앱"; toolFilter = nil; selection.removeAll() }
                    Button("내 프로세스") { scope = "내 프로세스"; selection.removeAll() }
                    Button("전체 프로세스") { scope = "전체 프로세스"; selection.removeAll() }
                }
                Text("\(rows.count)개").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                Spacer()
                DonySearchField(placeholder: "이름 검색", text: $search).frame(width: 160)
                DonyChoices(options: ["메모리순", "CPU순"], selection: Binding(get: { memorySort ? "메모리순" : "CPU순" }, set: { memorySort = $0 == "메모리순" })).frame(width: 170)
                SelectionControl(selection: $selection, ids: selectableRows.map(\.id)).disabled(model.busy)
            }
            if !selectedRows.isEmpty {
                HStack { Text("\(selectedRows.count)개 선택").font(Theme.font(13, weight: .medium)); Spacer(); Button("선택한 앱 종료") { model.quitSelected(selectedRows.map(\.process)); selection.removeAll() }.buttonStyle(PrimaryButton()).disabled(model.busy) }
            }
            if rows.isEmpty {
                EmptyState(icon: "waveform.path.ecg", title: "표시할 항목이 없어요", subtitle: "검색 조건을 바꾸거나 다음 시스템 측정을 기다려 주세요.")
            } else {
                LazyVStack(spacing: 0) {
                    HStack {
                        Text("앱 / 프로세스"); Spacer(); Text("CPU").help("앱 CPU는 코어당 100% 기준").frame(width: 70, alignment: .trailing); Text(scope == "내 앱" ? "메모리 합산" : "메모리").frame(width: 90, alignment: .trailing); Text("관리").frame(width: 100, alignment: .trailing)
                    }.font(Theme.font(10, weight: .medium)).foregroundStyle(Theme.secondary).padding(.horizontal, 18).padding(.vertical, 12).background(Theme.canvas)
                    ForEach(displayedRows) { row in
                        HStack(spacing: 10) {
                            Toggle("선택 " + row.name, isOn: Binding(get: { selection.contains(row.id) }, set: { if $0 { selection.insert(row.id) } else { selection.remove(row.id) } })).toggleStyle(DonyCheckbox()).labelsHidden().accessibilityLabel("선택 " + row.name).disabled(!model.canQuit(row.process) || model.busy)
                            Group {
                                if let icon = row.icon { Image(nsImage: icon).resizable().scaledToFit() }
                                else { DonyIcon("gearshape.2", size: 20).foregroundStyle(Theme.secondary).padding(5) }
                            }.frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name).font(Theme.font(12, weight: .medium)).lineLimit(1)
                                Text(scope == "내 앱" ? "프로세스 \(row.count)개" : "PID \(row.process.pid)").font(Theme.font(9)).foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(DisplayFormat.percent(row.cpu)).foregroundStyle((row.cpu ?? 0) > 85 ? Theme.amber : Theme.ink).frame(width: 70, alignment: .trailing)
                            Text(row.memory >= 0 ? DisplayFormat.bytes(row.memory) : "—").frame(width: 90, alignment: .trailing)
                            HStack(spacing: 5) {
                                if model.canQuit(row.process) {
                                    Button("종료") { model.quit(row.process) }.buttonStyle(QuietButton()).disabled(model.operationBusy)
                                    DonyIconMenu(title: "프로세스 작업") { Button("강제 종료…", role: .destructive) { model.quit(row.process, force: true) } }.disabled(model.operationBusy)
                                } else { DonyIcon("lock").foregroundStyle(Theme.secondary).help("직접 종료할 수 없는 시스템 또는 백그라운드 프로세스") }
                            }.frame(width: 100, alignment: .trailing)
                        }.font(Theme.font(11)).monospacedDigit().frame(height: 56).padding(.horizontal, 18)
                        Divider().padding(.leading, 56)
                    }
                }.panel(0)
                if rows.count > 100 { Text("상위 100개를 표시합니다. 검색으로 특정 프로세스를 찾을 수 있어요.").font(Theme.font(10)).foregroundStyle(Theme.secondary) }
            }
            DisclosureGroup("시스템 상세 정보") {
                HStack { Text("스왑 " + (model.snapshot.swapUsed.map(DisplayFormat.bytes) ?? "—")); Spacer(); Text("압축 메모리 " + (model.snapshot.memoryCompressed.map(DisplayFormat.bytes) ?? "—")) }.font(Theme.font(12)).padding(.vertical, 12)
                Text("앱 메모리 합산에는 공유 메모리가 중복될 수 있어요").font(Theme.font(11)).foregroundStyle(Theme.secondary)
                HStack { Spacer(); Button("활동 모니터 열기") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }.buttonStyle(QuietButton()) }
            }.font(Theme.font(12)).tint(Theme.secondary).panel(20)
        }.onAppear {
            if let tool = model.performanceTool { toolFilter = tool; search = ""; scope = "내 앱"; model.performanceTool = nil }
            else { toolFilter = nil }
        }
    }
}
