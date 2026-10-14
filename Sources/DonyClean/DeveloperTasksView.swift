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
                Text("CLI 작업").font(Theme.font(18, weight: .semibold))
                    .help("로컬 작업 폴더와 시작 정보를 확인한 CLI만 표시해요. 현재 제어 호스트·작업 폴더는 보호해요.")
                Spacer(minLength: 12)
                Button { controller.update(model.snapshot) } label: { Text("새로고침").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(controller.busy)
            }
            DonyFilterChips(options: ["전체"] + AITool.allCases.filter { model.connectedTools.contains($0) }.map(\.title), selection: Binding(
                get: { model.developmentToolFilter?.title ?? "전체" },
                set: { value in model.developmentToolFilter = AITool.allCases.first { $0.title == value } }
            )).disabled(controller.busy)
            if let message = controller.message {
                HStack(spacing: 12) {
                    DonyIcon("info.circle", size: 18).foregroundStyle(Theme.primary)
                    Text(message).font(Theme.font(13)).fixedSize(horizontal: false, vertical: true)
                    if controller.busy { ProgressView().controlSize(.small) }
                }.frame(maxWidth: .infinity, alignment: .leading).panel(16)
            }
            if visibleTasks.isEmpty {
                EmptyState(icon: "terminal", title: "제어할 수 있는 CLI 작업이 없습니다", subtitle: "")
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
                    VStack(spacing: 0) {
                        ForEach(Array(recoveredOnly.enumerated()), id: \.element.id) { index, record in
                            recoveryRow(record)
                            if index < recoveredOnly.count - 1 { Divider() }
                        }
                    }.panel(0)
                }
            }
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
            HStack(spacing: 12) {
                Button(controller.isOwned(task) ? "재개" : "일시 정지") {
                    if controller.isOwned(task) { controller.resume(task.id) } else { controller.pause(task) }
                }.buttonStyle(QuietButton()).help("일시 정지는 CPU 실행을 멈추지만 RAM은 유지해요.")
                DonyTextAction(title: "중단") { controller.stop(task) }
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
