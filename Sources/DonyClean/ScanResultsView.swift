import SwiftUI
import DonyCore

struct ScanResultsView: View {
    @EnvironmentObject var model: AppModel
    private var headerPlan: RecommendedPlan { model.recommendedPlan(includeCleanup: model.cleanCaches, includeDuplicates: model.cleanCopies, includeDeveloper: model.cleanDeveloper, includeWorkspaces: model.cleanWorkspaces) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                PageHeader(title: model.smart == nil ? "전체 검사" : "검사 결과")
                if let smart = model.smart, !smart.cancelled, headerPlan.items.count > 0 {
                    DonyTextAction(title: "다시 검사") { model.scanSmart() }.disabled(model.busy)
                    Button("선택 항목 정리 · " + DisplayFormat.bytes(headerPlan.bytes)) { model.runRecommended(includeCleanup: model.cleanCaches, includeDuplicates: model.cleanCopies, includeDeveloper: model.cleanDeveloper, includeWorkspaces: model.cleanWorkspaces) }.buttonStyle(PrimaryButton()).disabled(model.busy)
                } else {
                    Button(model.smart == nil ? "검사 시작" : "다시 검사") { model.scanSmart() }.buttonStyle(PrimaryButton()).disabled(model.busy)
                }
            }.frame(height: 42)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("파일 검사 폴더").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    Text(model.folder.path).font(Theme.font(13)).lineLimit(1).truncationMode(.middle).help(model.folder.path)
                }
                Spacer()
                DonyTextAction(title: "폴더 변경") { model.chooseFolder() }.disabled(model.busy)
            }.panel(20)
            if model.activity?.title == "전체 검사" || model.smart != nil { SmartScanStatusView() }
            if model.smart == nil { CleanupOutcomeCard() }
            if model.smart != nil { SmartCareView() }
            else if model.activity == nil {
                VStack(alignment: .leading, spacing: 14) {
                    Text("캐시·로그와 선택한 폴더의 파일을 검사해요.").font(Theme.font(16, weight: .semibold))
                    Text("검사가 끝나면 정리할 항목을 선택할 수 있어요.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                }.panel()
            }
        }
    }
}
