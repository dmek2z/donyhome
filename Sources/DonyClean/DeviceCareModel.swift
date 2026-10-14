import SwiftUI
import AppKit
import UserNotifications
import DonyCore

extension AppModel {
    func updateStorageCare(_ snapshot: SystemSnapshot) {
        storageAssessment = StorageAssessment.resolve(available: snapshot.diskAvailable, total: snapshot.diskTotal, warningGB: storageWarningGB, recovering: storageAssessment.needsAttention)
        if !storageAssessment.needsAttention { storageReviewPending = false }
        if storageNoticeGate.update(storageAssessment, now: Date(), enabled: storageAlertsEnabled) {
            UserDefaults.standard.set(storageNoticeGate.lastNotice, forKey: "lastStorageNotice")
            if notifyEnabled {
                let content = UNMutableNotificationContent(); content.title = "도니홈 · 저장 공간 부족"
                content.body = "남은 공간 " + (snapshot.diskAvailable.map(DisplayFormat.bytes) ?? "확인 필요") + " · 홈에서 정리 추천을 확인하세요."
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "storage-care", content: content, trigger: nil))
            }
        }
        if storageCheckGate.update(storageAssessment, now: Date(), enabled: automaticStorageCheck) { storageReviewPending = true }
        // Read-only recommendations; wait for an ongoing operation to finish.
        if storageReviewPending, automaticStorageCheck, permissionSetupReviewed, !onboardingShown, !busy, !permissionsShown {
            storageReviewPending = false
            scanStorageRecommendations()
        }
    }

    func scanStorageRecommendations() {
        guard let (token, epoch) = begin("공간 부족 정리 검사") else { return }
        let running = runningCleanupOwners; let report = progress(epoch); let days = projectRetentionDays
        Task {
            let value = await Task.detached(priority: .utility) {
                let result = AutomaticCleanup.scan(runningOwners: running, token: token, progress: report, days: days)
                var decisions: [String: CleanupDecision] = [:]
                for item in result.items { decisions[item.id] = try? CleanupPolicy(days: days).reason(for: item, runningBundleIDs: running, token: token) }
                return (result, decisions)
            }.value
            guard days == projectRetentionDays else { finish(true, issues: []); return }
            storageRecommendations = value.0; storageRecommendationDecisions = value.1; storageRecommendationDate = Date()
            finish(value.0.cancelled, issues: value.0.issues)
        }
    }
    func openStorageCare() {
        section = .cleanup
        scanCleanup()
    }
    func saveStorageCare() {
        storageWarningGB = max(1, min(1000, storageWarningGB))
        UserDefaults.standard.set(storageWarningGB, forKey: "storageWarningGB")
        UserDefaults.standard.set(storageAlertsEnabled, forKey: "storageAlertsEnabled")
        UserDefaults.standard.set(automaticStorageCheck, forKey: "automaticStorageCheck")
        updateStorageCare(snapshot)
    }
    func measureCleanupOutcome(records: [ActionRecord], before: Int64?, permanent: Bool = false) async {
        let after = await Task.detached(priority: .utility) { SystemSampler().sample() }.value
        snapshot = after; updateStorageCare(after)
        lastCleanupOutcome = CleanupOutcome(movedBytes: records.filter(\.success).reduce(0) { $0 + $1.bytes }, successful: records.filter(\.success).count, failed: records.filter { !$0.success }.count, beforeAvailable: before, afterAvailable: after.diskAvailable, permanent: permanent)
    }
}
struct DeviceCareStatusView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.storageAssessment.needsAttention {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.storageAssessment.title).font(Theme.font(16, weight: .semibold))
                        Text("남은 공간 " + (model.snapshot.diskAvailable.map(DisplayFormat.bytes) ?? "—") + " · 오래된 캐시와 로그부터 확인해요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }; Spacer()
                    Button { model.openStorageCare() } label: { Text("정리 추천").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(model.busy)
                }.panel(20)
            }
            if model.snapshot.pressure == .warning || model.snapshot.pressure == .critical {
                SettingsActionRow(title: "메모리 압박 · " + model.snapshot.pressure.label, actionTitle: "사용량 확인") { model.section = .performance }.panel(20)
            }
            CleanupOutcomeCard()
        }
    }
}
struct StorageCareSettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("공간 부족 관리").font(Theme.font(16, weight: .semibold))
            Toggle("공간 부족 알림", isOn: $model.storageAlertsEnabled).toggleStyle(DonySwitch())
            Toggle("공간 부족 시 캐시·로그 검사", isOn: $model.automaticStorageCheck).toggleStyle(DonySwitch())
            HStack { Text("알림 기준").font(Theme.font(14)); Spacer(); TextField("GB", value: $model.storageWarningGB, format: .number).textFieldStyle(.roundedBorder).frame(width: 72); Text("GB 이하").font(Theme.font(12)).foregroundStyle(Theme.secondary) }
        }.panel().onChange(of: model.storageAlertsEnabled) { _, _ in model.saveStorageCare() }.onChange(of: model.automaticStorageCheck) { _, _ in model.saveStorageCare() }.onChange(of: model.storageWarningGB) { _, _ in model.saveStorageCare() }
    }
}

struct CleanupOutcomeCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let outcome = model.lastCleanupOutcome {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(outcome.successful)개 " + (outcome.permanent ? "삭제" : "휴지통 이동") + " · " + DisplayFormat.bytes(outcome.movedBytes)).font(Theme.font(14, weight: .semibold))
                    Text("측정된 공간 변화 " + (outcome.observedDelta.map { ($0 >= 0 ? "+" : "−") + DisplayFormat.bytes(abs($0)) } ?? "측정 불가") + (outcome.failed > 0 ? " · \(outcome.failed)개 건너뜀" : "")).font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    if !outcome.permanent { Text("휴지통을 비워야 공간이 늘어요. 마음이 바뀌면 되돌릴 수 있어요.").font(Theme.font(12)).foregroundStyle(Theme.secondary) }
                }; Spacer()
                if !outcome.permanent {
                    if !model.lastCleanupRecords.isEmpty {
                        Button { model.restoreCleanup(model.lastCleanupRecords) } label: { Text("되돌리기").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(model.busy)
                    }
                    Button { model.scanTrash(); model.section = .tools } label: { Text("휴지통 비우기").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(model.busy)
                } else {
                    Button { model.section = .history } label: { Text("정리 기록").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton())
                }
            }.panel(20)
        }
    }
}
