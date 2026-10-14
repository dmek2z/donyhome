import SwiftUI
import AppKit
import DonyCore

extension AppModel {
    func scanTrash() {
        guard let (token, _) = begin("휴지통 목록 검사") else { return }
        Task {
            trashItems = await Task.detached(priority: .utility) { TrashEmptyService.scan(token: token) }.value
            trashDate = Date(); finish(trashItems.cancelled, issues: trashItems.issues)
        }
    }
    func emptyInspectedTrash() {
        Task { await emptyInspectedTrashAfterReview() }
    }
    private func emptyInspectedTrashAfterReview() async {
        guard !busy, !trashItems.cancelled, !trashItems.items.isEmpty else { return }
        let captured = trashItems.items
        let message = "\(captured.count)개 · \(DisplayFormat.bytes(trashItems.totalBytes))\n영구 삭제하며 휴지통에서 복원할 수 없습니다. 검사 후 새로 추가됐거나 변경된 항목은 삭제하지 않습니다."
        guard await confirm("검사한 휴지통 항목 영구 삭제", message: message, action: "영구 삭제", destructive: true, paths: captured.map(\.id)) else { return }
        guard !busy else { return }
        let spaceMeasurement = CleanupSpaceMeasurement()
        operationLabel = "검사한 휴지통 항목을 다시 확인하고 영구 삭제하는 중…"; operationBusy = true
        Task {
            var records: [ActionRecord] = []
            for item in captured {
                let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
                if running.contains(where: { $0.path == item.id || FileSafety.isWithin($0, root: item.url) }) {
                    records.append(ActionRecord(kind: "휴지통 영구 삭제", sourcePath: item.id, trashPath: nil, bytes: 0, success: false, message: "실행 중인 앱을 포함한 항목입니다.")); continue
                }
                records.append(await Task.detached(priority: .utility) { TrashEmptyService.remove(item, beforeMutation: { spaceMeasurement.captureBeforeMutation() }) }.value)
            }
            let warning = append(records)
            await measureCleanupOutcome(records: records, before: spaceMeasurement.beforeAvailable, permanent: true)
            trashItems = await Task.detached(priority: .utility) { TrashEmptyService.scan(token: ScanToken()) }.value
            trashDate = Date(); operationBusy = false; sample()
            let summary = "\(records.filter(\.success).count)개 휴지통 항목을 영구 삭제했습니다. 실패·건너뜀 \(records.filter { !$0.success }.count)개는 정리 기록에서 확인하세요."
            banner = OperationFeedback.compose(summary: summary, historyError: warning)
        }
    }
}
