import SwiftUI
import DonyCore

struct SmartCareView: View {
    @EnvironmentObject var model: AppModel
    @State private var cleanCaches = true
    @State private var cleanCopies = true
    @State private var cleanDeveloper = true
    private var plan: RecommendedPlan { model.recommendedPlan(includeCleanup: cleanCaches, includeDuplicates: cleanCopies, includeDeveloper: cleanDeveloper) }
    private var selectedCount: Int { plan.items.count }
    private var selectedBytes: Int64 { plan.bytes }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let smart = model.smart {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(smart.cancelled ? "검사 중단 · 일부 결과" : "검사 완료").font(Theme.font(18, weight: .semibold))
                        if let date = model.smartDate { Text(date, format: .dateTime.month().day().hour().minute()).font(Theme.font(12)).foregroundStyle(Theme.secondary) }
                    }
                    Spacer()
                    Chip(text: "정리 추천 \(model.recommendedPlan(includeCleanup: true, includeDuplicates: true).items.count)개", color: smart.cancelled ? Theme.amber : Theme.success)
                }
                if !model.blockedPaths.isEmpty {
                    HStack {
                        Text("접근 권한이 필요한 경로 \(Set(model.blockedPaths).count)개").font(Theme.font(13)).foregroundStyle(Theme.amber)
                        Spacer(); Button("권한 설정") { model.showPermissionGuidance() }.buttonStyle(QuietButton())
                    }
                }
                Text("정리할 항목 선택").font(Theme.font(15, weight: .semibold))
                VStack(spacing: 0) {
                    recommendedRow("오래된 캐시 · 로그", icon: "sparkles", detail: "\(model.recommendedCleanup.count)개 · " + DisplayFormat.bytes(model.recommendedCleanup.reduce(0) { $0 + $1.bytes }), selected: $cleanCaches, section: .cleanup, mode: "캐시 · 로그")
                    Divider()
                    recommendedRow("동일한 파일 사본", icon: "doc.on.doc", detail: "\(model.recommendedDuplicateCopies.count)개 · " + DisplayFormat.bytes(model.recommendedDuplicateCopies.reduce(0) { $0 + $1.bytes }), selected: $cleanCopies, section: .files, mode: "중복 파일")
                    Divider()
                    recommendedRow("개발 캐시", icon: "gearshape", detail: "\(model.recommendedDeveloper.count)개 · " + DisplayFormat.bytes(model.recommendedDeveloper.reduce(0) { $0 + $1.bytes }), selected: $cleanDeveloper, section: .development, mode: "캐시")
                    Divider()
                }.font(Theme.font(13))
                DisclosureGroup("직접 확인할 항목") {
                VStack(spacing: 0) {
                    reviewRow("큰 파일", icon: "folder", detail: "\(model.largeFiles.items.count)개 · " + DisplayFormat.bytes(model.largeFiles.totalBytes), section: .files, mode: "큰 파일")
                    Divider()
                    reviewRow("오래된 파일 · 설치 파일", icon: "doc.fill", detail: "\(model.clutter.oldFiles.items.count)개 · \(model.clutter.installers.items.count)개", section: .files, mode: "오래된 파일")
                    Divider()
                    reviewRow("유사 사진 후보", icon: "doc.fill", detail: "\(model.similar.groups.count)개 그룹", section: .files, mode: "유사 사진")
                    Divider()
                    reviewRow("남은 앱 파일", icon: "square.stack.3d.up", detail: "\(model.leftovers.items.count)개", section: .applications, mode: "남은 앱 파일")
                    Divider()
                    reviewRow("폴더 용량", icon: "externaldrive", detail: DisplayFormat.bytes(model.spaceMap.totalBytes), section: .space)
                    Divider()
                    reviewRow("휴지통", icon: "trash", detail: "\(model.trashItems.items.count)개 · " + DisplayFormat.bytes(model.trashItems.totalBytes), section: .tools)
                    Divider()
                    reviewRow("설치 앱", icon: "square.stack.3d.up", detail: "\(model.applications.apps.count)개", section: .applications, mode: "설치 앱")
                }
                }.font(Theme.font(13)).tint(Theme.secondary)
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(selectedCount)개 선택 · " + DisplayFormat.bytes(selectedBytes)).font(Theme.font(21, weight: .semibold))
                        Text("선택 항목은 휴지통으로 이동해요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("선택 항목 정리") { model.runRecommended(includeCleanup: cleanCaches, includeDuplicates: cleanCopies, includeDeveloper: cleanDeveloper) }.buttonStyle(PrimaryButton()).disabled(model.busy || smart.cancelled || selectedCount == 0)
                }.padding(.top, 8)
                DisclosureGroup("추천 기준") {
                    Text("보관 기간 \(model.projectRetentionDays)일 · 개별 파일 재확인 · 원본 보관").font(Theme.font(12)).foregroundStyle(Theme.secondary).padding(.top, 8)
                }.font(Theme.font(12)).tint(Theme.secondary)
                IssuesView(issues: smart.issues)
            }
        }.panel()
    }
    private func open(_ section: Section, mode: String?) {
        if let mode {
            switch section { case .cleanup: model.cleanupMode = mode; case .development: model.developmentMode = mode; case .files: model.filesMode = mode; case .applications: model.applicationsMode = mode; default: break }
        }
        model.section = section
    }
    private func recommendedRow(_ title: String, icon: String, detail: String, selected: Binding<Bool>, section: Section, mode: String? = nil) -> some View {
        HStack(spacing: 12) {
            Toggle(title, isOn: selected).toggleStyle(DonyCheckbox()).labelsHidden().accessibilityLabel(title).disabled(model.busy || detail.hasPrefix("0개"))
            DonyIcon(icon).foregroundStyle(section.iconColor)
            Text(title).font(Theme.font(14, weight: .medium)); Spacer()
            Text(detail).font(Theme.font(13)).foregroundStyle(Theme.secondary)
            Button("검토") { open(section, mode: mode) }.buttonStyle(QuietButton()).disabled(model.busy)
        }.padding(.vertical, 10)
    }
    private func reviewRow(_ title: String, icon: String, detail: String, section: Section, mode: String? = nil) -> some View {
        HStack(spacing: 12) {
            DonyIcon(icon).foregroundStyle(section.iconColor).padding(.leading, 32)
            Text(title).font(Theme.font(14, weight: .medium)); Spacer()
            Text(detail).font(Theme.font(13)).foregroundStyle(Theme.secondary)
            Button("직접 선택") { open(section, mode: mode) }.buttonStyle(QuietButton()).disabled(model.busy)
        }.padding(.vertical, 10)
    }
}
