import SwiftUI
import AppKit
import DonyCore

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @State private var expanded = Set<UUID>()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "정리 기록")
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(DisplayFormat.bytes(model.movedBytes)).font(Theme.font(29, weight: .semibold))
                    Text("누적 휴지통 이동").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                }; Spacer()
                Button("휴지통 열기") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
                }.buttonStyle(QuietButton())
            }.panel()
            Text("휴지통을 비워야 공간이 확보됩니다 · 정리 한 번을 한 줄로 묶어 보여줘요").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            if model.history.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", title: "정리 기록이 없어요", subtitle: "")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(groups) { group in
                        let restorable = group.records.filter { model.canRestore($0) }
                        HStack(spacing: 12) {
                            DonyIcon(group.failures == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(group.failures == 0 ? Theme.primary : Theme.amber)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(group)).font(Theme.font(14, weight: .medium)).lineLimit(1).truncationMode(.middle).help(group.first.sourcePath)
                                Text(subtitle(group)).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 12)
                            if !restorable.isEmpty {
                                Button { model.restoreCleanup(restorable) } label: { Text("되돌리기").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(model.busy)
                            }
                            if group.records.count == 1, let trash = group.first.trashPath, FileManager.default.fileExists(atPath: trash) {
                                Button { model.showFinder(URL(fileURLWithPath: trash)) } label: { Text("항목 보기").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton())
                            }
                            Button {
                                if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
                            } label: {
                                DonyIcon("chevron.right", size: 12).rotationEffect(.degrees(expanded.contains(group.id) ? 90 : 0)).frame(width: 32, height: 32).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("상세 보기").accessibilityLabel("정리 기록 상세").accessibilityValue(expanded.contains(group.id) ? "펼쳐짐" : "접힘")
                        }.padding(.horizontal, 24).frame(height: Theme.listRowHeight)
                        if expanded.contains(group.id) { details(group) }
                        Divider().padding(.leading, 56)
                    }
                }.panel(0)
            }
        }
    }
    /// 정리 한 번(같은 종류·성공 여부, 90초 안에 이어진 기록)을 묶은 단위.
    private struct RunGroup: Identifiable {
        let records: [ActionRecord]
        var id: UUID { records[0].id }
        var first: ActionRecord { records[0] }
        var count: Int { records.reduce(0) { $0 + ($1.count ?? 1) } }
        var bytes: Int64 { records.reduce(0) { $0 + $1.bytes } }
        var failures: Int { records.filter { !$0.success }.reduce(0) { $0 + ($1.count ?? 1) } }
    }
    private var groups: [RunGroup] {
        var result: [RunGroup] = []; var current: [ActionRecord] = []
        for record in model.history {
            if let last = current.last, last.kind != record.kind || last.success != record.success || abs(last.timestamp.timeIntervalSince(record.timestamp)) > 90 {
                result.append(RunGroup(records: current)); current = []
            }
            current.append(record)
        }
        if !current.isEmpty { result.append(RunGroup(records: current)) }
        return result
    }
    private func title(_ group: RunGroup) -> String {
        group.count == 1 ? group.first.kind + " · " + URL(fileURLWithPath: group.first.sourcePath).lastPathComponent : "\(group.first.kind) · \(group.count.formatted())개"
    }
    private func subtitle(_ group: RunGroup) -> String {
        var parts = [group.first.timestamp.formatted(.dateTime.month().day().hour().minute())]
        if group.bytes > 0 { parts.append(DisplayFormat.bytes(group.bytes)) }
        if group.failures > 0 { parts.append("실패 \(group.failures.formatted())개") }
        if group.records.contains(where: { $0.count != nil }) { parts.append("오래된 기록은 요약됨") }
        return parts.joined(separator: " · ")
    }
    @ViewBuilder private func details(_ group: RunGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if group.records.count == 1 {
                Text(group.first.sourcePath).font(Theme.font(11)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                Text(group.first.message).font(Theme.font(12)).foregroundStyle(group.first.success ? Theme.secondary : Theme.amber)
                if group.first.bytes > 0 { Text(DisplayFormat.bytes(group.first.bytes)).font(Theme.font(12, weight: .medium)) }
            } else {
                ForEach(group.records.prefix(50)) { record in
                    HStack(spacing: 12) {
                        Text(record.count == nil ? URL(fileURLWithPath: record.sourcePath).lastPathComponent : record.sourcePath).font(Theme.font(11)).foregroundStyle(record.success ? Theme.body : Theme.amber).lineLimit(1).truncationMode(.middle).help(record.sourcePath)
                        Spacer(minLength: 12)
                        if record.bytes > 0 { Text(DisplayFormat.bytes(record.bytes)).font(Theme.font(11)).foregroundStyle(Theme.secondary) }
                    }
                }
                if group.records.count > 50 { Text("외 \((group.records.count - 50).formatted())건").font(Theme.font(11)).foregroundStyle(Theme.secondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 56).padding(.bottom, 16)
    }
}
