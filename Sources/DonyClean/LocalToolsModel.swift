import SwiftUI
import AppKit
import DonyCore

extension AppModel {
    func scanSimilar() {
        guard let (token, epoch) = begin("유사 사진 검사") else { return }
        smart = nil; smartDate = nil
        let root = folder; let report = progress(epoch)
        Task {
            similar = await Task.detached(priority: .utility) { SimilarPhotoFinder.find(root: root, token: token, progress: report) }.value
            similarDate = Date(); finish(similar.cancelled, issues: similar.issues)
        }
    }
    func retainSimilar(_ candidate: FileCandidate, in group: SimilarGroup) {
        guard let (token, _) = begin("보관할 사진 변경") else { return }
        Task {
            do {
                let changed = try await Task.detached(priority: .utility) { try SimilarPhotoFinder.replacingOriginal(in: group, with: candidate, token: token) }.value
                if let index = similar.groups.firstIndex(where: { $0.id == group.id }) { similar.groups[index] = changed }
            } catch { banner = error.localizedDescription }
            finish(token.isCancelled, issues: [])
        }
    }
    func scanDeveloper() {
        guard let (token, _) = begin("개발 캐시 검사") else { return }
        smart = nil; smartDate = nil
        let bundleIDs = runningBundleIDs; let days = projectRetentionDays
        Task {
            developer = await Task.detached(priority: .utility) { DeveloperCleanup.scan(runningTools: RunningTools.read().union(bundleIDs), token: token, days: days) }.value
            if days != projectRetentionDays { developer = DeveloperResult(); finish(true, issues: []); return }
            developerDate = Date(); finish(developer.cancelled, issues: developer.issues)
        }
    }
    func scanLeftovers() {
        guard let (token, _) = begin("남은 앱 파일 검사") else { return }
        let running = runningBundleIDs
        Task {
            let result = await Task.detached(priority: .utility) {
                let inventory = ApplicationScanner.inventory(token: token)
                let leftovers = LeftoverScanner.scan(installedIDs: Set(inventory.apps.map(\.bundleID)), runningIDs: running, token: token)
                return (inventory, leftovers)
            }.value
            applications = result.0; inventoryDate = Date(); leftovers = result.1; leftoverDate = Date()
            finish(leftovers.cancelled, issues: leftovers.issues + applications.issues)
        }
    }
    func scanClutter() {
        guard let (token, epoch) = begin("오래된 파일 · 설치 파일 검사") else { return }
        smart = nil; smartDate = nil
        let root = folder; let report = progress(epoch)
        Task {
            clutter = await Task.detached(priority: .utility) { ClutterScanner.scan(root: root, token: token, progress: report) }.value
            clutterDate = Date(); finish(clutter.oldFiles.cancelled || clutter.installers.cancelled, issues: clutter.oldFiles.issues + clutter.installers.issues)
        }
    }
    func scanSpace(_ chosen: URL? = nil) {
        let chosen = chosen ?? folder
        guard chosen.path == folder.path || FileSafety.isWithin(chosen, root: folder) else { banner = "선택한 검사 폴더 안에서만 탐색할 수 있습니다."; return }
        guard let (token, epoch) = begin("폴더 용량 검사") else { return }
        spaceRoot = chosen; spaceMap = SpaceResult(); spaceDate = nil
        let report = progress(epoch)
        Task {
            spaceMap = await Task.detached(priority: .utility) { SpaceMap.scan(root: chosen, token: token, progress: report) }.value
            spaceDate = Date(); finish(spaceMap.cancelled, issues: spaceMap.issues)
        }
    }
    func refreshSnapshots() {
        guard !busy else { return }; operationLabel = "로컬 스냅샷 목록 읽는 중…"; operationBusy = true
        Task {
            do {
                localSnapshots = try await Task.detached(priority: .utility) { try Maintenance.listSnapshots() }.value
                snapshotsDate = Date()
            } catch { banner = "스냅샷 목록을 읽지 못했습니다: " + error.localizedDescription }
            operationBusy = false
        }
    }
    func runMaintenance(_ task: MaintenanceTask) {
        guard !busy else { return }
        let message: String
        switch task {
        case .flushDNS: message = "DNS와 mDNS 캐시를 초기화합니다. 사이트 연결 문제를 해결할 때 실행하세요. macOS 관리자 인증이 필요합니다."
        case .reindexSpotlight: message = "시동 디스크의 Spotlight 색인을 다시 만듭니다. 재색인 동안 CPU와 디스크 사용량이 늘 수 있습니다. macOS 관리자 인증이 필요합니다."
        case .deleteSnapshot(let date):
            guard localSnapshots.contains(date) else { banner = "스냅샷 목록을 다시 확인해 주세요."; return }
            message = "선택한 로컬 Time Machine 스냅샷 " + date + "를 영구 제거합니다. 이 백업 시점은 복구할 수 없습니다. 다른 스냅샷과 외부 백업은 유지합니다. macOS 관리자 인증이 필요합니다."
        }
        guard confirm(task.title, message: message, action: "실행", destructive: true) else { return }
        operationLabel = task.title + " · 시스템 인증 또는 작업 완료 대기 중…"
        operationBusy = true; maintenanceOutput = nil
        Task {
            let result: CommandResult
            do {
                result = try await Task.detached(priority: .utility) {
                    if case .deleteSnapshot(let date) = task { guard try Maintenance.listSnapshots().contains(date) else { throw DonyError.changed } }
                    return try Maintenance.execute(task) { try CommandRunner.run($0) }
                }.value
            } catch { result = CommandResult(status: -1, output: error.localizedDescription) }
            maintenanceOutput = result.output.isEmpty ? (result.success ? "시스템 명령이 완료됐습니다." : "작업이 완료되지 않았습니다.") : result.output
            let warning = append([ActionRecord(kind: task.title, sourcePath: "macOS", trashPath: nil, bytes: 0, success: result.success, message: maintenanceOutput ?? "")])
            banner = OperationFeedback.compose(summary: task.title + (result.success ? " 명령이 완료됐습니다." : " 실행이 취소되거나 실패했습니다."), historyError: warning)
            operationBusy = false; sample()
            if case .deleteSnapshot = task { refreshSnapshots() }
        }
    }
}
