import Foundation
import AppKit
import DonyCore

extension AppModel {
    var toolStorageCurrent: Bool {
        toolStorageDate != nil && !toolStorage.cancelled &&
            toolStorageTools == connectedTools && toolStorageDays == projectRetentionDays
    }
    func scanToolStorage() {
        guard let (token, epoch) = begin("개발 도구 캐시·로그 검사") else { return }
        let tools = connectedTools; let running = Set(aiUsage.map(\.tool))
        let days = projectRetentionDays; let report = progress(epoch)
        toolStorageDate = nil
        Task {
            let result = await Task.detached(priority: .utility) {
                ToolStorage.scan(tools: tools, runningTools: running, days: days, token: token, progress: report)
            }.value
            toolStorage = result; toolStorageTools = tools; toolStorageDays = days; toolStorageDate = Date()
            finish(result.cancelled, issues: result.issues)
        }
    }
    func reviewDevelopmentTasks(_ tool: AITool? = nil) {
        developmentToolFilter = tool; developmentMode = "작업"; section = .development
        developmentPressureReview = false
    }
    func reviewToolMemory(_ tool: AITool?) {
        performanceTool = tool; section = .performance
    }
    func cleanToolStorage(_ ids: Set<String>) {
        guard !busy, toolStorageCurrent else { banner = "도구 또는 보관 기간이 바뀌었어요. 다시 검사해 주세요."; return }
        let items = toolStorage.eligible.filter { ids.contains($0.id) }
        guard !items.isEmpty, items.count == ids.count else { return }
        let bytes = items.reduce(0) { $0 + $1.candidate.bytes }
        guard confirm("개발 도구 캐시·로그 정리", message: "\(items.count)개 · \(DisplayFormat.bytes(bytes))를 휴지통으로 이동합니다. 대화·인증·프로젝트 원본은 제외하며 실행 중인 도구는 다시 확인합니다. 휴지통에서 복원할 수 있습니다.", action: "휴지통으로 이동", destructive: true, paths: items.map(\.id)) else { return }
        let days = toolStorageDays
        let measurement = CleanupSpaceMeasurement()
        operationBusy = true; operationLabel = "개발 도구 상태를 다시 확인하는 중…"
        Task {
            var records: [ActionRecord] = []
            for item in items {
                let mapping = aiApplicationTools
                let originals = duplicateOriginals.values.map { $0.url.path } + similarOriginals.map { $0.url.path }
                let record = await Task.detached(priority: .utility) {
                    do {
                        guard !originals.contains(item.id) else { throw DonyError.missingOriginal }
                        let snapshot = SystemSampler().sample()
                        let owners = Set(AITool.usage(snapshot.processes, currentUID: getuid(), applicationTools: mapping).map(\.tool))
                        let token = ScanToken()
                        try ToolStorage.validate(item, runningTools: owners, days: days, token: token)
                        return TrashService.move(item.candidate, token: token, beforeMutation: { measurement.captureBeforeMutation() })
                    } catch {
                        return ActionRecord(kind: "개발 도구 정리", sourcePath: item.id, trashPath: nil, bytes: 0, success: false, message: error.localizedDescription)
                    }
                }.value
                records.append(record)
            }
            let historyError = append(records)
            await measureCleanupOutcome(records: records, before: measurement.beforeAvailable)
            let success = records.filter(\.success)
            banner = OperationFeedback.compose(summary: "\(success.count)개 · \(DisplayFormat.bytes(success.reduce(0) { $0 + $1.bytes })) 휴지통 이동 · \(records.count - success.count)개 건너뜀", historyError: historyError)
            toolStorage = ToolStorageResult(); toolStorageDate = nil
            operationBusy = false; sample()
        }
    }
}
