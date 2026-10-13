import SwiftUI
import AppKit
import DonyCore

struct ApplicationsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    @State private var search = ""
    private var apps: [InstalledApplication] { model.applications.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    private var selected: [FileCandidate] { model.appFiles.items.filter { selection.contains($0.id) } }
    private var appRunning: Bool {
        guard let app = model.inspectedApp else { return false }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleID && !$0.isTerminated }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "앱 관리")
            HStack {
                Button { model.openLoginSettings() } label: { DonyLabel("로그인 · 백그라운드 앱 관리", icon: "power") }.buttonStyle(QuietButton())
                Spacer(); Button { model.scanApplications() } label: { DonyLabel("앱 목록 새로고침", icon: "arrow.clockwise") }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }
            HStack { Text("\(model.applications.apps.count)개 사용자 설치 앱").font(Theme.font(13, weight: .semibold)); Spacer(); TextField("앱 검색", text: $search).textFieldStyle(.roundedBorder).frame(width: 210) }
            if model.applications.cancelled { Chip(text: "중단됨 · 일부 결과", color: Theme.amber) }
            if apps.isEmpty {
                EmptyState(icon: "square.stack.3d.up", title: "표시할 앱이 없어요", subtitle: model.inventoryDate == nil ? "앱 목록을 확인하는 중입니다." : "검색 조건 또는 설치된 앱 경로를 확인해 주세요.")
            } else {
                HStack(alignment: .top, spacing: 16) {
                    LazyVStack(spacing: 0) {
                        ForEach(apps) { app in
                            Button { model.inspect(app) } label: {
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().scaledToFit().frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(app.name).font(Theme.font(12, weight: .medium)).lineLimit(1)
                                        Text("버전 " + app.version).font(Theme.font(10)).foregroundStyle(Theme.secondary)
                                    }; Spacer(); DonyIcon("chevron.right", size: 12).foregroundStyle(Theme.secondary)
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(model.inspectedApp?.id == app.id ? Theme.blueWash : .white)
                            }.buttonStyle(.plain).disabled(model.busy)
                            Divider().padding(.leading, 54)
                        }
                    }.frame(width: 260).panel(0)
                    VStack(alignment: .leading, spacing: 14) {
                        if let app = model.inspectedApp {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(app.name).font(Theme.font(19, weight: .semibold))
                                Text(app.bundleID).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                                Text("관련 파일에 설정·사용자 데이터 포함").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                                if appRunning { Chip(text: "실행 중 · 종료 후 제거 가능", color: Theme.amber) }
                            }.panel(16)
                            if !model.appFiles.items.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(model.appFiles.items) { candidate in
                                        CandidateRow(candidate: candidate, selection: $selection)
                                        Divider().padding(.leading, 58)
                                    }
                                }.panel(0)
                                SelectionBar(selected: selected) { model.moveToTrash(selected, ownerBundleID: app.bundleID) }.disabled(appRunning)
                            } else if model.activity == nil {
                                EmptyState(icon: "doc.text.magnifyingglass", title: "선택 가능한 파일이 없어요", subtitle: "접근 권한 또는 아래 검사 결과를 확인해 주세요.")
                            }
                            IssuesView(issues: model.appFiles.issues)
                        } else {
                            EmptyState(icon: "app.badge.checkmark", title: "앱을 선택해 주세요", subtitle: "")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            IssuesView(issues: model.applications.issues)
        }.onChange(of: model.scanEpoch) { _, _ in selection.removeAll() }
            .task { if model.inventoryDate == nil && !model.busy { model.scanApplications() } }
    }
}
