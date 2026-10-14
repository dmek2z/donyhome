import Foundation
import Darwin
import AppKit
import DonyCore

extension AppModel {
    /// GUI 앱이 아닌 내 CLI 프로세스(셸·claude·ssh·.app 내부·시스템 경로 제외).
    func canTerminateCLI(_ process: ProcessReading) -> Bool {
        NSRunningApplication(processIdentifier: process.pid) == nil && CLIProcessPolicy.isEligible(process, currentUID: getuid(), ownPID: getpid())
    }
    var cliFindingIDs: [String] {
        CLIProcessPolicy.findings(snapshot.processes, currentUID: getuid(), ownPID: getpid()).map(\.id)
    }
    func terminateCLI(_ processes: [ProcessReading]) {
        Task { await terminateCLIAfterReview(processes) }
    }
    private func terminateCLIAfterReview(_ processes: [ProcessReading]) async {
        let eligible = processes.filter { canTerminateCLI($0) }
        guard !busy, !eligible.isEmpty else { return }
        guard await confirm("프로세스 \(eligible.count)개 종료", message: "일반 종료 신호(SIGTERM)를 보냅니다. 저장되지 않은 작업이 있는 프로세스인지 확인해 주세요. 강제 종료는 하지 않습니다.", action: "종료 요청", destructive: true, paths: eligible.map { $0.name + " · PID \($0.pid)" }) else { return }
        guard !busy else { return }
        let before = snapshot
        var records: [ActionRecord] = []
        for process in eligible {
            do {
                try ProcessPolicy.verifyIdentity(process)
                guard canTerminateCLI(process) else { throw DonyError.protectedProcess }
                guard kill(process.pid, SIGTERM) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                records.append(ActionRecord(kind: "프로세스 종료 요청", sourcePath: process.path, trashPath: nil, bytes: 0, success: true, message: "일반 종료를 요청했습니다."))
            } catch { records.append(ActionRecord(kind: "프로세스 종료 요청", sourcePath: process.path, trashPath: nil, bytes: 0, success: false, message: error.localizedDescription)) }
        }
        let warning = append(records)
        banner = OperationFeedback.compose(summary: "\(records.filter(\.success).count)개 프로세스에 종료를 요청했습니다. 실제 종료와 사용량 변화는 시스템 수치에서 확인하세요.", historyError: warning)
        try? await Task.sleep(for: .seconds(3))
        sample()
        try? await Task.sleep(for: .seconds(1))
        lastRelief = ReliefObservation(app: "선택한 프로세스", before: before, after: snapshot)
    }
}
