import SwiftUI
import DonyCore

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    private var plan: RecommendedPlan { model.recommendedPlan(includeCleanup: true, includeDuplicates: true) }
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                HomeCareArtwork(activity: model.busy ? .working : CharacterActivity.resolve(cpu: model.snapshot.cpuPercent, pressure: model.snapshot.pressure), mode: model.characterMode)
                VStack(spacing: 9) {
                    Text("오늘도 가볍게 시작해요").font(Theme.font(28, weight: .bold)).tracking(-0.6)
                    Text("Mac 상태부터 정리할 항목까지 한 번에 확인해요.")
                        .font(Theme.font(14)).foregroundStyle(Theme.secondary)
                }.multilineTextAlignment(.center)
                Button { model.scanSmart() } label: {
                    HStack(spacing: 9) {
                        if model.busy { ProgressView().controlSize(.small).tint(.white) }
                        Text(model.busy ? (model.activity != nil ? "검사 중" : "작업 중") : "전체 검사")
                    }.frame(minWidth: Theme.actionWidth - 32)
                }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 8)

            DeviceCareStatusView()
            if let smart = model.smart {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(smart.cancelled ? "중단된 검사 · 일부 결과" : "최근 검사 결과").font(Theme.font(15, weight: .semibold))
                        Text("정리 추천 \(plan.items.count)개 · \(DisplayFormat.bytes(plan.bytes))")
                            .font(Theme.font(13)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 12)
                    Button { model.section = .inspection } label: { Text("결과 보기").frame(width: Theme.actionWidth - 24) }
                        .buttonStyle(QuietButton()).disabled(model.busy)
                }.panel(20)
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    Text("지금 Mac 상태").font(Theme.font(16, weight: .semibold))
                    Spacer(minLength: 12)
                    Button { model.section = .performance } label: { Text("CPU · 메모리 보기").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton())
                }
                HStack(alignment: .top, spacing: 20) {
                    resource("CPU 사용량", value: DisplayFormat.percent(model.snapshot.cpuPercent), detail: "전체 코어", icon: "cpu")
                    resource("메모리 사용량", value: model.snapshot.memoryUsed.map(DisplayFormat.bytes) ?? "—", detail: "메모리 압박 · " + model.snapshot.pressure.label, icon: "memorychip", color: model.pressureColor)
                    resource("남은 저장 공간", value: model.snapshot.diskAvailable.map(DisplayFormat.bytes) ?? "—", detail: "전체 " + (model.snapshot.diskTotal.map(DisplayFormat.bytes) ?? "—"), icon: "externaldrive")
                }
                Divider()
                SettingsActionRow(title: "개발 도구와 로컬 프로젝트", actionTitle: "개발 보기") { model.section = .development }
            }.panel()
        }.frame(maxWidth: .infinity)
    }
    private func resource(_ title: String, value: String, detail: String, icon: String, color: Color = Theme.primary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                DonyIcon(icon, size: 15).foregroundStyle(color)
                Text(title).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            Text(value).font(Theme.font(21, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(detail).font(Theme.font(12)).foregroundStyle(Theme.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
