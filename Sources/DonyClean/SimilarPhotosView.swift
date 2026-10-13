import SwiftUI
import AppKit
import DonyCore

struct SimilarPhotosView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    private var selected: [FileCandidate] { model.similar.groups.flatMap { $0.copies.map(\.candidate) }.filter { selection.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "파일 정리")
            DonyTabs(options: ["큰 파일", "중복 파일", "오래된 파일", "설치 파일", "유사 사진"], selection: $model.filesMode).disabled(model.busy)
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text(model.folder.path).font(Theme.font(12)).lineLimit(1).truncationMode(.middle); Text("\(model.similar.groups.count)개 유사 사진 그룹").font(Theme.font(17, weight: .semibold)) }
                Spacer(); Button("폴더 선택") { model.chooseFolder() }.buttonStyle(QuietButton()).disabled(model.busy)
                Button("사진 검사") { model.scanSimilar() }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }.panel()
            Text("비슷해 보여도 다른 순간의 사진일 수 있어요. 미리보기를 비교하고 보관할 사진을 골라주세요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            if model.similar.cancelled { Chip(text: "중단됨 · 일부 비교 결과", color: Theme.amber) }
            if model.similarDate == nil { EmptyState(icon: "doc.on.doc", title: "유사 사진을 검사해 주세요", subtitle: "") }
            else if model.similar.groups.isEmpty { EmptyState(icon: "checkmark.circle", title: "유사 사진 후보가 없어요", subtitle: "") }
            else {
                ForEach(model.similar.groups) { group in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { DonyIcon("lock.fill").foregroundStyle(Theme.primary); Text("보관 · " + group.original.name).font(Theme.font(14, weight: .semibold)); Spacer() }
                        PhotoThumbnail(url: group.original.url).frame(height: 160).frame(maxWidth: .infinity).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 10))
                        ForEach(group.copies, id: \.candidate.id) { match in
                            HStack(spacing: 14) {
                                Toggle("선택 " + match.candidate.name, isOn: Binding(get: { selection.contains(match.candidate.id) }, set: { if $0 { selection.insert(match.candidate.id) } else { selection.remove(match.candidate.id) } })).toggleStyle(DonyCheckbox()).labelsHidden().accessibilityLabel("선택 " + match.candidate.name).disabled(model.busy)
                                PhotoThumbnail(url: match.candidate.url).frame(width: 100, height: 85).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 5) { Text(match.candidate.name).font(Theme.font(13, weight: .medium)); Text(DisplayFormat.bytes(match.candidate.bytes)).font(Theme.font(12)).foregroundStyle(Theme.secondary) }
                                Spacer(); Button("이 사진 보관") { model.retainSimilar(match.candidate, in: group) }.buttonStyle(QuietButton()).disabled(model.busy)
                                Button { model.showFinder(match.candidate.url) } label: { DonyIcon("arrow.up.forward.square") }.buttonStyle(.plain)
                            }
                        }
                    }.panel()
                }
                SelectionBar(selected: selected) {
                    let originals = Dictionary(uniqueKeysWithValues: model.similar.groups.flatMap { group in group.copies.map { ($0.candidate.id, group.original) } })
                    model.moveToTrash(selected, originals: originals)
                }
            }
            IssuesView(issues: model.similar.issues)
        }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll() }
    }
}
struct PhotoThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group { if let image { Image(nsImage: image).resizable().scaledToFit() } else { DonyIcon("doc.fill", size: 30).foregroundStyle(Theme.secondary) } }
            .task(id: url) {
                let value = await Task.detached(priority: .utility) { try? SimilarPhotoFinder.thumbnail(url, pixels: 400) }.value
                if let value { image = NSImage(cgImage: value, size: .zero) }
            }
    }
}
