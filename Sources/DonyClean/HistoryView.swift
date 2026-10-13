import SwiftUI
import AppKit
import DonyCore

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
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
                        HStack(alignment: .top, spacing: 12) {
                            DonyIcon(record.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(record.success ? Theme.primary : Theme.amber).font(Theme.font(16)).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(record.kind + " · " + URL(fileURLWithPath: record.sourcePath).lastPathComponent).font(Theme.font(12, weight: .semibold)).lineLimit(1)
                                    Spacer(); Text(record.timestamp, format: .dateTime.month().day().hour().minute()).font(Theme.font(10)).foregroundStyle(Theme.secondary)
                                }
                                DisclosureGroup("상세") {
                                Text(record.sourcePath).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                                Text(record.message).font(Theme.font(11)).foregroundStyle(record.success ? Theme.secondary : Theme.amber)
                                if record.bytes > 0 { Text(DisplayFormat.bytes(record.bytes)).font(Theme.font(11, weight: .medium)) }
                                }.font(Theme.font(11)).tint(Theme.secondary)
                                if let trash = record.trashPath, FileManager.default.fileExists(atPath: trash) {
                                    HStack { Spacer(); Button("항목 보기") { model.showFinder(URL(fileURLWithPath: trash)) }.buttonStyle(QuietButton()) }
                                }
                            }
                        }.padding(18); Divider().padding(.leading, 45)
                    }
                }.panel(0)
            }
        }
    }
}
