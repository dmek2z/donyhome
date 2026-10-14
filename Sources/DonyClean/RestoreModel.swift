import Foundation
import DonyCore

extension AppModel {
    func restoreCleanup(_ records: [ActionRecord]) {
        guard !busy, !records.isEmpty else { return }
        operationLabel = "원래 위치로 되돌리는 중…"; operationBusy = true
        Task {
            let results = await Task.detached(priority: .utility) { records.map { TrashRestore.restore($0) } }.value
            let warning = append(results)
            let done = results.filter(\.success).count
            let restoredSources = Set(results.filter(\.success).map(\.sourcePath))
            lastCleanupRecords.removeAll { restoredSources.contains($0.sourcePath) }
            if done > 0 { lastCleanupOutcome = nil; smart = nil; smartDate = nil; scanEpoch = UUID() }
            operationBusy = false; sample()
            let failed = results.count - done
            banner = OperationFeedback.compose(summary: "\(done)개 항목을 원래 위치로 되돌렸어요." + (failed > 0 ? " \(failed)개는 되돌리지 못했어요. " + (results.first { !$0.success }?.message ?? "") : ""), historyError: warning)
        }
    }
    func canRestore(_ record: ActionRecord) -> Bool {
        guard record.success, record.kind == "휴지통 이동", let trash = record.trashPath else { return false }
        return FileManager.default.fileExists(atPath: trash) && !FileManager.default.fileExists(atPath: record.sourcePath)
    }
}
