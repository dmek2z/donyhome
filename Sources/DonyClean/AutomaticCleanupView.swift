import SwiftUI

struct AutomaticCleanupView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("안전 자동 정리").font(Theme.font(18, weight: .semibold))
                Spacer()
                Button("지금 자동 정리") { model.runAutomaticCleanup() }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }
            Text("캐시 14일 · 로그 30일 · 휴지통 이동").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            Toggle("하루 한 번 자동 정리", isOn: Binding(get: { model.automaticCleanupEnabled }, set: { model.setAutomaticCleanup($0) })).toggleStyle(DonySwitch())
            if let summary = model.automaticCleanupSummary { Text(summary).font(Theme.font(12, weight: .medium)) }
            if let date = model.lastAutomaticCleanup {
                Text("다음 자동 검사: " + date.addingTimeInterval(86400).formatted(date: .abbreviated, time: .shortened)).font(Theme.font(11)).foregroundStyle(Theme.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}
