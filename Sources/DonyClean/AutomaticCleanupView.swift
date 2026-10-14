import SwiftUI

struct AutomaticCleanupView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsActionRow(title: "자동 정리", actionTitle: "지금 정리", enabled: !model.busy) { model.runAutomaticCleanup() }
            Text("보관 기간 \(model.projectRetentionDays)일").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            Toggle("하루 한 번 자동 정리", isOn: Binding(get: { model.automaticCleanupEnabled }, set: { model.setAutomaticCleanup($0) })).toggleStyle(DonySwitch())
            if let summary = model.automaticCleanupSummary { Text(summary).font(Theme.font(12, weight: .medium)) }
            if let date = model.lastAutomaticCleanup {
                Text("다음 자동 검사: " + date.addingTimeInterval(86400).formatted(date: .abbreviated, time: .shortened)).font(Theme.font(11)).foregroundStyle(Theme.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel(24)
    }
}
