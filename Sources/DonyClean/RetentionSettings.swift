import SwiftUI
import DonyCore

extension AppModel {
    func retentionChanged() {
        let bounded = max(1, min(3650, projectRetentionDays))
        if bounded != projectRetentionDays { projectRetentionDays = bounded; return }
        UserDefaults.standard.set(projectRetentionDays, forKey: "projectRetentionDays")
        cancel()
        cleanup = ScanResult(); cleanupInventory = []; cleanupDecisions = [:]; cleanupDate = nil
        developer = DeveloperResult(); developerDate = nil
        toolStorage = ToolStorageResult(); toolStorageDate = nil
        projectScan = ScanResult(); projectScanDate = nil; projectSummary = nil
        smart = nil; smartDate = nil
        storageRecommendations = ScanResult(); storageRecommendationDecisions = [:]; storageRecommendationDate = nil
    }
}

struct RetentionSettingsRow: View {
    @EnvironmentObject var model: AppModel
    @State private var shown = false
    var body: some View {
        SettingsActionRow(title: "보관 기간 · \(model.projectRetentionDays)일", actionTitle: "설정", enabled: !model.busy) { shown = true }
            .help("캐시·로그·개발 캐시·도구·프로젝트 추천에 공통 적용")
            .sheet(isPresented: $shown) { RetentionSettingsSheet() }
    }
}

struct RetentionSettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("보관 기간").font(Theme.font(20, weight: .semibold))
                Spacer()
                DonyTextAction(title: "완료") { dismiss() }
            }
            HStack {
                Text("공통 추천 기준").font(Theme.font(14, weight: .medium))
                Spacer()
                Button("−") { model.projectRetentionDays -= 1 }.buttonStyle(QuietButton()).disabled(model.projectRetentionDays <= 1)
                TextField("일", value: $model.projectRetentionDays, format: .number)
                    .textFieldStyle(.plain).font(Theme.font(18, weight: .semibold)).multilineTextAlignment(.center)
                    .frame(width: 64, height: Theme.controlHeight).background(.white).clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                Text("일").font(Theme.font(14))
                Button("+") { model.projectRetentionDays += 1 }.buttonStyle(QuietButton()).disabled(model.projectRetentionDays >= 3650)
            }.disabled(model.busy)
            DonyChoices(options: ["1일", "3일", "7일", "14일", "30일", "90일"], selection: Binding(
                get: { "\(model.projectRetentionDays)일" },
                set: { model.projectRetentionDays = Int($0.dropLast()) ?? 14 }
            )).disabled(model.busy)
        }.padding(24).frame(width: 520).foregroundStyle(Theme.body).background(Theme.canvas).preferredColorScheme(.light)
    }
}
