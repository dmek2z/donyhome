import SwiftUI
import AppKit
import DonyCore

extension AppModel {
    func retentionChanged() {
        let bounded = max(1, min(3650, projectRetentionDays))
        if bounded != projectRetentionDays { projectRetentionDays = bounded; return }
        UserDefaults.standard.set(projectRetentionDays, forKey: "projectRetentionDays")
        cancel()
        cleanup = ScanResult(); cleanupInventory = []; cleanupIncomplete = false; cleanupDecisions = [:]; cleanupDate = nil
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
        SettingsActionRow(title: "정리 기준 · \(model.projectRetentionDays)일 이상 안 쓴 항목", actionTitle: "변경", enabled: !model.busy) { shown = true }
            .help("캐시·로그·개발 캐시·도구·프로젝트 추천에 공통 적용")
            .sheet(isPresented: $shown) { RetentionSettingsSheet() }
    }
}

struct RetentionSettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("정리 기준").font(Theme.font(22, weight: .bold))
                Text("얼마나 안 쓴 항목부터 정리를 추천할까요?").font(Theme.font(14)).foregroundStyle(Theme.secondary)
            }
            VStack(spacing: 18) {
                HStack(spacing: 20) {
                    Button { model.projectRetentionDays -= 1 } label: { Text("−").frame(width: 24) }.buttonStyle(QuietButton()).disabled(model.projectRetentionDays <= 1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TextField("일", value: $model.projectRetentionDays, format: .number)
                            .textFieldStyle(.plain).font(Theme.font(44, weight: .bold)).multilineTextAlignment(.center).frame(width: 110)
                        Text("일 이상 안 쓴 항목").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.secondary)
                    }
                    Button { model.projectRetentionDays += 1 } label: { Text("+").frame(width: 24) }.buttonStyle(QuietButton()).disabled(model.projectRetentionDays >= 3650)
                }.frame(maxWidth: .infinity)
                DonyChoices(options: ["3일", "7일", "14일", "30일", "90일"], selection: Binding(
                    get: { "\(model.projectRetentionDays)일" },
                    set: { model.projectRetentionDays = Int($0.dropLast()) ?? 14 }
                ))
            }.disabled(model.busy).padding(24).frame(maxWidth: .infinity).background(.white).clipShape(RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 8) {
                Toggle("실행 중인 도구의 캐시도 정리", isOn: $model.cleanRunningToolFiles).toggleStyle(DonySwitch()).disabled(model.busy)
                Text("도구가 켜져 있어도 열려 있지 않은 오래된 캐시를 정리해요. 드물게 도구가 잠시 느려질 수 있어요.").font(Theme.font(12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 4)
            Text("모든 정리에 적용돼요. 이 기간 안에 쓴 항목은 추천에서 빼요.").font(Theme.font(12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("완료") { dismiss() }.buttonStyle(PrimaryButton()) }
        }
        // 열리자마자 숫자 입력칸이 선택된 상태가 되지 않게 한다.
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { NSApp.keyWindow?.makeFirstResponder(nil) } }
        .padding(28).frame(width: 480).foregroundStyle(Theme.body).background(Theme.canvas).preferredColorScheme(.light)
    }
}
