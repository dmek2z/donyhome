import Foundation
import Darwin
import DonyCore

extension AppModel {
    var cliFindings: [CLIProcessPolicy.Finding] {
        CLIProcessPolicy.findings(snapshot.processes, currentUID: getuid(), ownPID: getpid())
    }
    func terminateCLI(_ findings: [CLIProcessPolicy.Finding]) {
        guard !busy, !findings.isEmpty else { return }
        guard confirm("개발 프로세스 \(findings.count)개 종료", message: "일반 종료 신호(SIGTERM)를 보냅니다. 저장되지 않은 작업이 있는 프로세스인지 확인해 주세요. 강제 종료는 하지 않습니다.", action: "종료 요청", destructive: true, paths: findings.map { $0.process.name + " · PID \($0.process.pid) · " + $0.reason }) else { return }
        let before = snapshot
        var records: [ActionRecord] = []
        for finding in findings {
            let process = finding.process
            do {
                try ProcessPolicy.verifyIdentity(process)
                guard CLIProcessPolicy.isEligible(process, currentUID: getuid(), ownPID: getpid()) else { throw DonyError.protectedProcess }
                guard kill(process.pid, SIGTERM) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                records.append(ActionRecord(kind: "개발 프로세스 종료 요청", sourcePath: process.path, trashPath: nil, bytes: 0, success: true, message: finding.reason + " · 일반 종료를 요청했습니다."))
            } catch { records.append(ActionRecord(kind: "개발 프로세스 종료 요청", sourcePath: process.path, trashPath: nil, bytes: 0, success: false, message: error.localizedDescription)) }
        }
        let warning = append(records)
        banner = OperationFeedback.compose(summary: "\(records.filter(\.success).count)개 프로세스에 종료를 요청했습니다. 실제 종료와 사용량 변화는 시스템 수치에서 확인하세요.", historyError: warning)
        Task {
            try? await Task.sleep(for: .seconds(3))
            sample()
            try? await Task.sleep(for: .seconds(1))
            lastRelief = ReliefObservation(app: "개발 프로세스", before: before, after: snapshot)
        }
    }
}
