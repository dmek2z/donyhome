import SwiftUI
import DonyCore

struct DeveloperTasksView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var controller = AgentTaskController.shared
    private var visibleTasks: [AgentTaskGroup] { controller.tasks.filter { model.developmentToolFilter == nil || $0.tool == model.developmentToolFilter } }
    private var recoveredOnly: [OwnedAgentTask] { controller.owned.filter { record in !controller.tasks.contains { $0.id == record.id } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLI 작업").font(Theme.font(18, weight: .semibold))
                    Text("도구와 작업 폴더를 확인한 CLI 프로세스만 표시합니다.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 12)
                DonyMenuButton(title: model.developmentToolFilter?.title ?? "모든 도구", width: Theme.filterWidth) {
                    Button("모든 도구") { model.developmentToolFilter = nil }
                    ForEach(AITool.allCases.filter { model.connectedTools.contains($0) }) { tool in Button(tool.title) { model.developmentToolFilter = tool } }
                }.disabled(controller.busy)
                Button { controller.update(model.snapshot) } label: { Text("새로고침").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(controller.busy)
            }
            if let message = controller.message {
                HStack(spacing: 12) {
                    DonyIcon("info.circle", size: 18).foregroundStyle(Theme.primary)
                    Text(message).font(Theme.font(13)).fixedSize(horizontal: false, vertical: true)
                    if controller.busy { ProgressView().controlSize(.small) }
                }.frame(maxWidth: .infinity, alignment: .leading).panel(16)
            }
            if visibleTasks.isEmpty {
                EmptyState(icon: "terminal", title: "제어할 수 있는 CLI 작업이 없습니다", subtitle: "Codex · Claude · Hermes · OpenCode · Gemini · Aider · Copilot · cursor-agent의 작업 폴더와 프로세스를 확인하면 여기에 표시됩니다.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(task)
                        if index < visibleTasks.count - 1 { Divider().padding(.leading, 20) }
                    }
                }.panel(0)
            }
            if !recoveredOnly.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("이전 일시 정지 기록").font(Theme.font(16, weight: .semibold))
                    Text("현재 목록에서 연결하지 못한 기록입니다. 재개할 때 동일한 시작 정보가 확인되는 프로세스에만 신호를 보냅니다.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(recoveredOnly.enumerated()), id: \.element.id) { index, record in
                            recoveryRow(record)
                            if index < recoveredOnly.count - 1 { Divider() }
                        }
                    }.panel(0)
                }
            }
            Text("일시 정지는 CPU 실행을 멈추도록 요청하지만 RAM을 비우지 않습니다. GUI 앱·터미널·tmux·오케스트레이터와 현재 도니홈·제어 호스트 및 사용 중인 작업 폴더는 제외합니다. ChatGPT의 클라우드 작업 수나 앱 내부 에이전트 작업은 여기에서 제어할 수 없습니다. 앱 관리는 CPU · 메모리 화면에서 확인해 주세요.")
                .font(Theme.font(12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }.onAppear { controller.update(model.snapshot) }
            .onChange(of: model.snapshot.timestamp) { _, _ in controller.update(model.snapshot) }
    }
    private func taskRow(_ task: AgentTaskGroup) -> some View {
        HStack(spacing: 14) {
            DonyIcon("terminal", size: 19).foregroundStyle(Theme.primary).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.tool.title).font(Theme.font(14, weight: .semibold))
                    Text("PID \(task.root.pid) · \(task.members.count)개 프로세스").font(Theme.font(11)).foregroundStyle(Theme.secondary)
                    if controller.isOwned(task) { Text("일시 정지 요청됨").font(Theme.font(11, weight: .medium)).foregroundStyle(Theme.amber) }
                }
                Text(task.workingDirectory).font(Theme.font(12)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle).help(task.workingDirectory)
            }
            Spacer(minLength: 8)
            Text(DisplayFormat.bytes(task.memoryBytes)).font(Theme.font(13, weight: .medium)).monospacedDigit().frame(width: 80, alignment: .trailing)
            DonyMenuButton(title: "작업 관리") {
                if controller.isOwned(task) { Button("재개 요청") { controller.resume(task.id) } }
                else { Button("일시 정지 요청") { controller.pause(task) } }
                Button("중단 요청", role: .destructive) { controller.stop(task) }
            }.disabled(controller.busy || controller.recoveryUnavailable)
        }.padding(.horizontal, 20).frame(height: Theme.listRowHeight)
    }
    private func recoveryRow(_ record: OwnedAgentTask) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.tool.title + " · " + "\(record.members.count)개 기록").font(Theme.font(14, weight: .semibold))
                Text(record.workingDirectory).font(Theme.font(12)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle).help(record.workingDirectory)
            }
            Spacer(minLength: 12)
            Button { controller.resume(record.id) } label: { Text("재개 검토").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(controller.busy || controller.recoveryUnavailable)
        }.padding(.horizontal, 20).frame(height: Theme.listRowHeight)
    }
}
