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
    @State private var memorySort = false
    @State private var search = ""
    @State private var selection = Set<String>()
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
        output = output.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.process.pid).contains(search) }
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
                MetricCard(title: "전체 CPU", symbol: "cpu", value: DisplayFormat.percent(model.snapshot.cpuPercent), detail: "전체 코어 기준 · 최근 사용량", values: model.cpuHistory)
                MetricCard(title: "메모리 압박", symbol: "memorychip", value: model.snapshot.pressure.label, detail: "사용 " + (model.snapshot.memoryUsed.map(DisplayFormat.bytes) ?? "—") + " / " + DisplayFormat.bytes(model.snapshot.memoryTotal), color: model.pressureColor, values: model.memoryHistory)
                MetricCard(title: "스왑 사용", symbol: "arrow.left.arrow.right", value: model.snapshot.swapUsed.map(DisplayFormat.bytes) ?? "—", detail: "압축 메모리 " + (model.snapshot.memoryCompressed.map(DisplayFormat.bytes) ?? "—"), color: Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    DonyIcon("memorychip", size: 24).foregroundStyle(Theme.primary)
                    Text("앱을 종료해 사용량 줄이기").font(Theme.font(15, weight: .semibold))
                    Spacer()
                    Button("메모리순 보기") { memorySort = true; scope = "내 앱"; search = "" }.buttonStyle(QuietButton())
                }
                HStack {
                    Button("사용량 높은 앱 선택") {
                        scope = "내 앱"; search = ""
                        selection = Set(rows.filter { model.canQuit($0.process) && (($0.cpu ?? 0) >= 50 || $0.memory >= 1_000_000_000) }.map(\.id))
                    }.buttonStyle(QuietButton()).disabled(model.busy)
                    Text("\(selectedRows.count)개 선택").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("선택한 앱 종료") { model.quitSelected(selectedRows.map(\.process)); selection.removeAll() }.buttonStyle(PrimaryButton()).disabled(selectedRows.isEmpty || model.busy)
                }
            }.panel()
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
                DonyTabs(options: ["내 앱", "내 프로세스", "전체 프로세스"], selection: Binding(get: { scope }, set: { scope = $0; selection.removeAll() }))
                Spacer()
                HStack(spacing: 6) { DonyIcon("magnifyingglass").foregroundStyle(Theme.secondary); TextField("앱 이름 또는 PID", text: $search).textFieldStyle(.plain) }.font(Theme.font(11)).padding(9).background(.white).clipShape(RoundedRectangle(cornerRadius: 8)).frame(width: 160)
            }
            HStack {
                Text("\(rows.count)개 " + (scope == "내 앱" ? "앱" : "프로세스")).font(Theme.font(12, weight: .medium))
                Spacer(); Button(memorySort ? "메모리순 ↓" : "CPU순 ↓") { memorySort.toggle() }.buttonStyle(QuietButton())
            }
            if rows.isEmpty {
                EmptyState(icon: "waveform.path.ecg", title: "표시할 항목이 없어요", subtitle: "검색 조건을 바꾸거나 다음 시스템 측정을 기다려 주세요.")
            } else {
                LazyVStack(spacing: 0) {
                    HStack {
                        Text("앱 / 프로세스"); Spacer(); Text("CPU").frame(width: 70, alignment: .trailing); Text(scope == "내 앱" ? "메모리 합산" : "메모리").frame(width: 90, alignment: .trailing); Text("관리").frame(width: 100, alignment: .trailing)
                    }.font(Theme.font(10, weight: .medium)).foregroundStyle(Theme.secondary).padding(.horizontal, 18).padding(.vertical, 12).background(Theme.canvas)
                    ForEach(Array(rows.prefix(100))) { row in
                        HStack(spacing: 10) {
                            Toggle("선택 " + row.name, isOn: Binding(get: { selection.contains(row.id) }, set: { if $0 { selection.insert(row.id) } else { selection.remove(row.id) } })).toggleStyle(DonyCheckbox()).labelsHidden().accessibilityLabel("선택 " + row.name).disabled(!model.canQuit(row.process) || model.busy)
                            Group {
                                if let icon = row.icon { Image(nsImage: icon).resizable().scaledToFit() }
                                else { DonyIcon("gearshape.2", size: 20).foregroundStyle(Theme.secondary).padding(5) }
                            }.frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name).font(Theme.font(12, weight: .medium)).lineLimit(1)
                                Text("PID \(row.process.pid)" + (scope == "내 앱" ? " · 프로세스 \(row.count)개" : "")).font(Theme.font(9)).foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(DisplayFormat.percent(row.cpu)).foregroundStyle((row.cpu ?? 0) > 85 ? Theme.amber : Theme.ink).frame(width: 70, alignment: .trailing)
                            Text(row.memory >= 0 ? DisplayFormat.bytes(row.memory) : "—").frame(width: 90, alignment: .trailing)
                            HStack(spacing: 5) {
                                if model.canQuit(row.process) {
                                    Button("종료") { model.quit(row.process) }.buttonStyle(QuietButton()).disabled(model.operationBusy)
                                    Menu { Button("강제 종료…", role: .destructive) { model.quit(row.process, force: true) } } label: { DonyIcon("ellipsis") }.menuStyle(.borderlessButton).frame(width: 16).disabled(model.operationBusy)
                                } else { DonyIcon("lock").foregroundStyle(Theme.secondary).help("직접 종료할 수 없는 시스템 또는 백그라운드 프로세스") }
                            }.frame(width: 100, alignment: .trailing)
                        }.font(Theme.font(11)).monospacedDigit().padding(.horizontal, 18).padding(.vertical, 12)
                        Divider().padding(.leading, 56)
                    }
                }.panel(0)
                if rows.count > 100 { Text("상위 100개를 표시합니다. 검색으로 특정 프로세스를 찾을 수 있어요.").font(Theme.font(10)).foregroundStyle(Theme.secondary) }
            }
            Text("앱 CPU: 코어당 100% · 메모리 합산: 공유 메모리 중복 가능").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            Button("활동 모니터 열기") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }.buttonStyle(QuietButton())
        }
    }
}
