import SwiftUI
import DonyCore

struct FilesView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode = "큰 파일"
    @State private var selection = Set<String>()
    private var items: [FileCandidate] { mode == "큰 파일" ? model.largeFiles.items : model.duplicates.groups.flatMap(\.copies) }
    private var selected: [FileCandidate] { items.filter { selection.contains($0.id) } }
    private var scanned: Bool { mode == "큰 파일" ? model.filesDate != nil : model.duplicateDate != nil }
    private var issues: [ScanIssue] { mode == "큰 파일" ? model.largeFiles.issues : model.duplicates.issues }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "큰 파일 · 중복")
            HStack(spacing: 12) {
                DonyIcon("folder.fill").font(Theme.font(22)).foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.folder.lastPathComponent).font(Theme.font(14, weight: .semibold))
                    Text(model.folder.path).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                Spacer(); Button("폴더 선택") { model.chooseFolder() }.buttonStyle(QuietButton()).disabled(model.busy)
            }.panel()
            HStack {
                DonyTabs(options: ["큰 파일", "중복 파일"], selection: $mode).disabled(model.busy)
                Spacer(); Button { model.scanFiles(duplicatesOnly: mode == "중복 파일") } label: { DonyLabel(mode + " 검사", icon: "magnifyingglass") }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }
            Text(mode == "큰 파일" ? "100 MB 이상" : "원본 1개는 보관").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            if (mode == "큰 파일" ? model.largeFiles.cancelled : model.duplicates.cancelled) { Chip(text: "중단됨 · 일부 결과", color: Theme.amber) }
            if !scanned {
                EmptyState(icon: mode == "큰 파일" ? "doc.text.magnifyingglass" : "doc.on.doc", title: "검사를 시작해 주세요", subtitle: "")
            } else if items.isEmpty {
                EmptyState(icon: "checkmark.circle", title: "찾은 파일이 없어요", subtitle: issues.isEmpty ? "현재 검사 범위에서 조건에 맞는 파일을 찾지 못했습니다." : "건너뛴 경로가 있습니다. 아래 내용을 확인해 주세요.")
            } else if mode == "큰 파일" {
                Text("\(items.count)개 파일 · \(DisplayFormat.bytes(items.reduce(0) { $0 + $1.bytes }))").font(Theme.font(12, weight: .semibold))
                LazyVStack(spacing: 0) { ForEach(items) { file in CandidateRow(candidate: file, selection: $selection); Divider().padding(.leading, 58) } }.panel(0)
            } else {
                Text("\(model.duplicates.groups.count)개 그룹 · 중복 사본 \(items.count)개").font(Theme.font(12, weight: .semibold))
                LazyVStack(spacing: 14) {
                    ForEach(model.duplicates.groups) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 10) {
                                DonyIcon("lock.fill").foregroundStyle(Theme.primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("보관할 원본 · " + group.original.name).font(Theme.font(12, weight: .semibold))
                                    Text(group.original.url.path).font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle).help(group.original.url.path)
                                }; Spacer(); Button { model.showFinder(group.original.url) } label: { DonyIcon("arrow.up.forward.square") }.buttonStyle(.plain)
                            }.padding(16).background(Theme.blueWash.opacity(0.6))
                            ForEach(group.copies) { file in CandidateRow(candidate: file, selection: $selection); Divider().padding(.leading, 58) }
                        }.panel(0)
                    }
                }
            }
            if !items.isEmpty {
                SelectionBar(selected: selected) {
                    var originals: [String: FileCandidate] = [:]
                    for group in model.duplicates.groups { for copy in group.copies { originals[copy.id] = group.original } }
                    model.moveToTrash(selected, originals: originals)
                }
            }
            IssuesView(issues: issues)
        }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll() }.onChange(of: mode) { _, _ in selection.removeAll() }
    }
}
