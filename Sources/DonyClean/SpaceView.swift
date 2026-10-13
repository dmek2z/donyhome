import SwiftUI
import DonyCore

struct SpaceView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    @State private var hoveredEntry: String?
    private var selected: [FileCandidate] { model.spaceMap.entries.filter(\.selectable).map(\.candidate).filter { selection.contains($0.id) } }
    private let colors: [Color] = [Theme.primary, Color(hex: 0x25b79a), Color(hex: 0x8662ed), Color(hex: 0xf5a623), Color(hex: 0xf45b78)]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "용량 지도")
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text((model.spaceRoot ?? model.folder).path).font(Theme.font(13)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Text(DisplayFormat.bytes(model.spaceMap.totalBytes)).font(Theme.font(28, weight: .semibold))
                }
                Spacer()
                if let root = model.spaceRoot, root.path != model.folder.path { Button("상위 폴더") { model.scanSpace(root.deletingLastPathComponent()) }.buttonStyle(QuietButton()).disabled(model.busy) }
                Button("폴더 선택") { model.chooseFolder() }.buttonStyle(QuietButton()).disabled(model.busy)
                Button("검사") { model.scanSpace(model.spaceRoot) }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.panel()
            if model.spaceMap.cancelled { Chip(text: "중단됨 · 일부 용량", color: Theme.amber) }
            if model.spaceDate == nil {
                EmptyState(icon: "externaldrive", title: "폴더 용량을 검사해 주세요", subtitle: "")
            } else if model.spaceMap.entries.isEmpty {
                EmptyState(icon: "folder", title: "표시할 항목이 없어요", subtitle: "")
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(Array(model.spaceMap.entries.prefix(10).enumerated()), id: \.element.id) { index, entry in
                            Rectangle().fill(colors[index % colors.count]).opacity(hoveredEntry == nil || hoveredEntry == entry.id ? 1 : 0.65).frame(width: max(0, (geometry.size.width - 20) * Double(entry.bytes) / Double(max(1, model.spaceMap.totalBytes))))
                                .onHover { hoveredEntry = $0 ? entry.id : nil }
                                .onTapGesture { if !model.busy { if entry.candidate.fingerprint.isDirectory { model.scanSpace(entry.candidate.url) } else { model.showFinder(entry.candidate.url) } } }
                                .help(entry.candidate.name + " · " + DisplayFormat.bytes(entry.bytes))
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                }.frame(height: 36)
                Text(model.spaceMap.entries.first(where: { $0.id == hoveredEntry }).map { $0.candidate.name + " · " + DisplayFormat.bytes($0.bytes) } ?? " ").font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1).frame(height: 16)
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.spaceMap.entries.prefix(200).enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 10) {
                            Toggle("선택 " + entry.candidate.name, isOn: Binding(get: { selection.contains(entry.id) }, set: { if $0 { selection.insert(entry.id) } else { selection.remove(entry.id) } })).toggleStyle(DonyCheckbox()).labelsHidden().accessibilityLabel("선택 " + entry.candidate.name).disabled(model.busy || !entry.selectable).help(entry.selectable ? "선택" : "미다운로드 클라우드 항목이 있어 삭제 선택 불가")
                            Circle().fill(colors[index % colors.count]).frame(width: 8, height: 8)
                            Button { if entry.candidate.fingerprint.isDirectory { model.scanSpace(entry.candidate.url) } else { model.showFinder(entry.candidate.url) } } label: {
                                HStack { DonyIcon(entry.candidate.fingerprint.isDirectory ? "folder" : "doc.fill"); Text(entry.candidate.name + (entry.selectable ? "" : " · 클라우드 포함")).lineLimit(1); Spacer() }.font(Theme.font(13)).foregroundStyle(Theme.body)
                            }.buttonStyle(.plain).disabled(model.busy)
                            Text(DisplayFormat.bytes(entry.bytes)).font(Theme.font(13, weight: .medium)).monospacedDigit()
                            DonyIcon("chevron.right", size: 12).foregroundStyle(Theme.secondary)
                        }.padding(16)
                        Divider().padding(.leading, 60)
                    }
                }.panel(0)
                if model.spaceMap.entries.count > 200 { Text("상위 200개 표시 · 하위 폴더에서 더 탐색할 수 있어요").font(Theme.font(12)).foregroundStyle(Theme.secondary) }
                SelectionBar(selected: selected) { model.moveToTrash(selected) }
            }
            IssuesView(issues: model.spaceMap.issues)
        }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll() }
    }
}
