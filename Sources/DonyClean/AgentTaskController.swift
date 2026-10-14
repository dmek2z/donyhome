import SwiftUI
import Foundation
import Darwin
import DonyCore

@MainActor final class AgentTaskController: ObservableObject {
    static let shared = AgentTaskController()
    @Published private(set) var tasks: [AgentTaskGroup] = []
    @Published private(set) var owned: [OwnedAgentTask] = []
    @Published private(set) var busy = false
    @Published private(set) var recoveryUnavailable = false
    @Published private(set) var message: String?
    private let control: AgentTaskControl
    private let callbacks: AgentTaskCallbacks
    private var refreshing = false
    private init() {
        let store = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DonyHome/paused-cli-tasks.json")
        callbacks = .live(store: store)
        var recovered: [OwnedAgentTask] = []
        var loadError: String?
        if FileManager.default.fileExists(atPath: store.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: store.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                      let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o022 == 0 else { throw AgentTaskError.unsafe }
                recovered = try JSONDecoder().decode([OwnedAgentTask].self, from: Data(contentsOf: store))
            } catch { loadError = "일시 정지 기록을 읽지 못했습니다. 기록을 확인하기 전에는 작업을 새로 정지하지 마세요. " + error.localizedDescription }
        }
        control = AgentTaskControl(currentUID: getuid(), ownPID: getpid(), callbacks: callbacks, owned: recovered)
        owned = control.ownedTasks
        if owned.count != recovered.count { loadError = "일시 정지 기록의 작업 정보를 검증하지 못했습니다. 원본 기록을 보존하며 제어 기능을 비활성화했습니다." }
        message = loadError; recoveryUnavailable = loadError != nil
    }
    func update(_ snapshot: SystemSnapshot) {
        guard !refreshing else { return }; refreshing = true
        let rows = snapshot.processes; let callbacks = callbacks
        Task {
            tasks = await Task.detached(priority: .utility) {
                AgentTaskControl.discover(rows, currentUID: getuid(), ownPID: getpid(), workingDirectory: callbacks.workingDirectory, rootTool: callbacks.rootTool)
            }.value
            owned = control.ownedTasks; refreshing = false
        }
    }
    func isOwned(_ task: AgentTaskGroup) -> Bool { owned.contains { $0.id == task.id } }
    func pause(_ task: AgentTaskGroup) {
        Task { await pauseAfterReview(task) }
    }
    private func pauseAfterReview(_ task: AgentTaskGroup) async {
        guard !busy, !recoveryUnavailable else { return }
        guard await ConfirmationDialog.show(title: "CLI 작업을 일시 정지할까요?", message: "CPU 실행을 멈추도록 요청합니다. RAM은 그대로 유지되며, 잠금과 네트워크 연결도 유지될 수 있습니다. 도니홈이 정지한 프로세스만 재개할 수 있습니다.", action: "일시 정지 요청", destructive: true, paths: paths(task)) else { return }
        guard !busy else { return }
        let control = control
        perform { try control.pause(task); return "일시 정지 요청됨 · \(task.members.count)개 프로세스. RAM은 유지됩니다." }
    }
    func resume(_ id: String) {
        Task { await resumeAfterReview(id) }
    }
    private func resumeAfterReview(_ id: String) async {
        guard !busy, !recoveryUnavailable, let record = owned.first(where: { $0.id == id }) else { return }
        guard await ConfirmationDialog.show(title: "CLI 작업을 재개할까요?", message: "도니홈의 일시 정지 기록과 현재 프로세스의 시작 정보를 다시 확인합니다. 종료됐거나 PID가 재사용된 프로세스에는 재개 신호를 보내지 않습니다.", action: "재개 요청", destructive: false, paths: [record.tool.title + " · " + record.workingDirectory] + record.members.map { "\($0.name) · PID \($0.pid)" }) else { return }
        guard !busy else { return }
        let control = control
        perform { let count = try control.resume(id: id); return count == 0 ? "기록된 프로세스가 이미 종료되었거나 변경되어 신호를 보내지 않았습니다." : "재개 요청됨 · \(count)개 프로세스" }
    }
    func stop(_ task: AgentTaskGroup) {
        Task { await stopAfterReview(task) }
    }
    private func stopAfterReview(_ task: AgentTaskGroup) async {
        guard !busy, !recoveryUnavailable else { return }
        guard await ConfirmationDialog.show(title: "CLI 작업을 중단할까요?", message: "SIGTERM으로 정상 종료를 요청합니다. 저장되지 않은 작업이나 진행 중인 출력이 사라질 수 있습니다. 종료가 확인됐다는 뜻은 아닙니다. 도니홈이 정지한 프로세스에는 종료 요청 후 재개 신호를 보내 종료를 진행시킵니다.", action: "중단 요청", destructive: true, paths: paths(task)) else { return }
        guard !busy else { return }
        let control = control
        perform { let count = try control.stop(task); return "중단 요청됨 · \(count)개 프로세스. 실제 종료 상태는 새로고침 후 확인해 주세요." }
    }
    private func paths(_ task: AgentTaskGroup) -> [String] {
        [task.tool.title + " · " + task.workingDirectory] + task.members.map { "\($0.name) · PID \($0.pid) · \($0.path)" }
    }
    private func perform(_ operation: @escaping @Sendable () throws -> String) {
        busy = true
        let callbacks = callbacks
        Task {
            do { message = try await Task.detached(priority: .userInitiated) { try operation() }.value }
            catch { message = error.localizedDescription }
            owned = control.ownedTasks
            tasks = await Task.detached(priority: .utility) {
                AgentTaskControl.discover(callbacks.snapshot(), currentUID: getuid(), ownPID: getpid(), workingDirectory: callbacks.workingDirectory, rootTool: callbacks.rootTool)
            }.value
            busy = false
        }
    }
    /// Parent app wires this synchronous best-effort recovery into applicationWillTerminate.
    /// Crash recovery stays manual in the UI; no launch-time SIGCONT is sent.
    func resumeOwnedTasksForShutdown() {
        guard !recoveryUnavailable else { return }
        for record in control.ownedTasks {
            do { _ = try control.resume(id: record.id) }
            catch { message = "앱 종료 시 일부 작업을 재개하지 못했습니다. 다음 실행의 복구 목록에서 확인해 주세요. " + error.localizedDescription }
        }
        owned = control.ownedTasks
    }
}
