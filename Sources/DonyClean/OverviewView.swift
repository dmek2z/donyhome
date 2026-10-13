import SwiftUI
import DonyCore

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    private var diskUsage: Double? {
        guard let total = model.snapshot.diskTotal, let available = model.snapshot.diskAvailable, total > 0 else { return nil }
        return Double(total - available) / Double(total)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                PageHeader(title: "한눈에 보기")
                Button { model.scanSmart() } label: { Text(model.smartDate == nil ? "스마트 점검" : "다시 점검") }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }
            HStack(spacing: 16) {
                MetricCard(title: "CPU 사용량", symbol: "cpu", value: DisplayFormat.percent(model.snapshot.cpuPercent), detail: "전체 코어", values: model.cpuHistory)
                MetricCard(title: "메모리 사용량", symbol: "memorychip", value: model.snapshot.memoryUsed.map(DisplayFormat.bytes) ?? "—", detail: "전체 " + DisplayFormat.bytes(model.snapshot.memoryTotal), color: model.pressureColor, values: model.memoryHistory)
                MetricCard(title: "남은 저장 공간", symbol: "externaldrive", value: model.snapshot.diskAvailable.map(DisplayFormat.bytes) ?? "—", detail: "전체 " + (model.snapshot.diskTotal.map(DisplayFormat.bytes) ?? "—"), progress: diskUsage)
            }
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("시스템 상태").font(Theme.font(18, weight: .semibold))
                    Spacer(); Text(model.snapshot.timestamp, style: .time).font(Theme.font(12)).foregroundStyle(Theme.secondary)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("메모리 압박").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                        Chip(text: model.snapshot.pressure.label, color: model.pressureColor)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("스왑 사용").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                        Text(model.snapshot.swapUsed.map(DisplayFormat.bytes) ?? "—").font(Theme.font(17, weight: .semibold)).monospacedDigit()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("실행 중인 프로세스").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                        Text("\(model.snapshot.processes.count)개").font(Theme.font(17, weight: .semibold))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button("CPU · 메모리 관리") { model.section = .performance }.buttonStyle(QuietButton())
                }
            }.panel()
            HStack(spacing: 16) {
                HStack(spacing: 12) {
                    DonyIcon("power").foregroundStyle(Theme.success)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("배터리").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        Text(model.snapshot.battery.map { String(format: "%.0f%%", $0.percent) + ($0.charging ? " · 충전 중" : $0.externalPower ? " · 전원 연결" : " · 배터리 사용") } ?? "측정 불가").font(Theme.font(14, weight: .medium))
                    }; Spacer()
                }.frame(maxWidth: .infinity).panel(20)
                HStack(spacing: 12) {
                    DonyIcon("arrow.left.arrow.right").foregroundStyle(Theme.primary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("네트워크 전송률").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        Text("↓ " + (model.snapshot.networkReceivedPerSecond.map { DisplayFormat.bytes(Int64($0)) + "/s" } ?? "—") + "   ↑ " + (model.snapshot.networkSentPerSecond.map { DisplayFormat.bytes(Int64($0)) + "/s" } ?? "—")).font(Theme.font(14, weight: .medium)).monospacedDigit()
                    }; Spacer()
                }.frame(maxWidth: .infinity).panel(20)
            }
            SmartCareView()
            AutomaticCleanupView()
            HStack(spacing: 16) {
                shortcut("큰 파일 · 중복", icon: "folder", target: .files)
                shortcut("앱 관리", icon: "square.stack.3d.up", target: .applications)
                shortcut("정리 기록", icon: "clock.arrow.circlepath", target: .history)
            }
        }
    }
    private func shortcut(_ title: String, icon: String, target: Section) -> some View {
        Button { model.section = target } label: {
            HStack(spacing: 12) {
                DonyIcon(icon).font(Theme.font(20)).foregroundStyle(Theme.primary)
                Text(title).font(Theme.font(14, weight: .medium)); Spacer(minLength: 0)
                DonyIcon("chevron.right", size: 12).foregroundStyle(Theme.secondary)
            }.frame(maxWidth: .infinity).panel(22)
        }.buttonStyle(.plain)
    }
}
