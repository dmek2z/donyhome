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
            Text("휴지통을 비워야 공간이 확보됩니다 · 최근 500건").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            if model.history.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", title: "정리 기록이 없어요", subtitle: "")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.history) { record in
                        HStack(spacing: 12) {
                            DonyIcon(record.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(record.success ? Theme.primary : Theme.amber)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.kind + " · " + URL(fileURLWithPath: record.sourcePath).lastPathComponent).font(Theme.font(14, weight: .medium)).lineLimit(1).truncationMode(.middle).help(record.sourcePath)
                                Text(record.timestamp, format: .dateTime.month().day().hour().minute()).font(Theme.font(11)).foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength: 12)
                            if model.canRestore(record) {
                                Button { model.restoreCleanup([record]) } label: { Text("되돌리기").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(model.busy)
                            }
                            if let trash = record.trashPath, FileManager.default.fileExists(atPath: trash) {
                                Button { model.showFinder(URL(fileURLWithPath: trash)) } label: { Text("항목 보기").frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton())
                            }
                            Button {
                                if expanded.contains(record.id) { expanded.remove(record.id) } else { expanded.insert(record.id) }
                            } label: {
                                DonyIcon("chevron.right", size: 12).rotationEffect(.degrees(expanded.contains(record.id) ? 90 : 0)).frame(width: 32, height: 32).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("상세 보기").accessibilityLabel("정리 기록 상세").accessibilityValue(expanded.contains(record.id) ? "펼쳐짐" : "접힘")
                        }.padding(.horizontal, 24).frame(height: Theme.listRowHeight)
                        if expanded.contains(record.id) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(record.sourcePath).font(Theme.font(11)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                                Text(record.message).font(Theme.font(12)).foregroundStyle(record.success ? Theme.secondary : Theme.amber)
                                if record.bytes > 0 { Text(DisplayFormat.bytes(record.bytes)).font(Theme.font(12, weight: .medium)) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 56).padding(.bottom, 16)
                        }
                        Divider().padding(.leading, 56)
                    }
                }.panel(0)
            }
        }
    }
}
