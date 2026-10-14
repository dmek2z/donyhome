import SwiftUI
import DonyCore

struct SmartCareView: View {
    @EnvironmentObject var model: AppModel
    private var plan: RecommendedPlan { model.recommendedPlan(includeCleanup: model.cleanCaches, includeDuplicates: model.cleanCopies, includeDeveloper: model.cleanDeveloper, includeWorkspaces: model.cleanWorkspaces) }
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
                    recommendedRow("오래된 캐시 · 로그", icon: "sparkles", detail: "\(model.recommendedCleanup.count)개 · " + DisplayFormat.bytes(model.recommendedCleanup.reduce(0) { $0 + $1.bytes }), selected: $model.cleanCaches, section: .cleanup, mode: "캐시 · 로그", reason: "30일 이상 지난 로그와 14일 이상 변경 없는 앱 캐시 · 실행 중인 앱 제외", review: model.recommendedCleanup.map(\.id))
                    Divider()
                    recommendedRow("동일한 파일 사본", icon: "doc.on.doc", detail: "\(model.recommendedDuplicateCopies.count)개 · " + DisplayFormat.bytes(model.recommendedDuplicateCopies.reduce(0) { $0 + $1.bytes }), selected: $model.cleanCopies, section: .files, mode: "중복 파일", reason: "내용이 같은 사본만 · 원본 한 개는 남겨요", review: model.recommendedDuplicateCopies.map(\.id))
                    Divider()
                    recommendedRow("방치된 작업공간", icon: "folder", detail: "\(model.recommendedWorkspaces.count)개 · " + DisplayFormat.bytes(model.recommendedWorkspaces.reduce(0) { $0 + $1.bytes }), selected: $model.cleanWorkspaces, section: .development, mode: "캐시", reason: "\(model.projectRetentionDays)일 이상 활동 없음 · 변경·미푸시 없음 · 휴지통에서 복원 가능", review: model.recommendedWorkspaces.map(\.id))
                    Divider()
                    recommendedRow("개발 캐시", icon: "gearshape", detail: "\(model.recommendedDeveloperCaches.count)개 · " + DisplayFormat.bytes(model.recommendedDeveloperCaches.reduce(0) { $0 + $1.bytes }), selected: $model.cleanDeveloper, section: .development, mode: "캐시", reason: "\(model.projectRetentionDays)일 이상 변경 없고 관련 도구가 종료된 재생성 가능 캐시", review: model.recommendedDeveloperCaches.map(\.id))
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
                    reviewRow("폴더 용량", icon: "externaldrive", detail: DisplayFormat.bytes(model.spaceMap.totalBytes), section: .files, mode: "폴더 용량")
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
                    Button("선택 항목 정리") { model.runRecommended(includeCleanup: model.cleanCaches, includeDuplicates: model.cleanCopies, includeDeveloper: model.cleanDeveloper, includeWorkspaces: model.cleanWorkspaces) }.buttonStyle(PrimaryButton()).disabled(model.busy || smart.cancelled || selectedCount == 0)
                }.padding(.top, 8)
                DisclosureGroup("추천 기준") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(model.projectRetentionDays)일 이상 안 쓴 항목 · 개별 파일 재확인 · 원본 보관\n작업공간: 활동 없음 · 커밋하지 않은 변경 없음 · 모든 커밋이 원격에 있음 · 사용 중인 프로세스 없음").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        if !model.excludedRecommendations.isEmpty {
                            HStack(spacing: 12) {
                                Text("추천에서 뺀 항목 \(model.excludedRecommendations.count)개").font(Theme.font(12, weight: .medium))
                                DonyTextAction(title: "초기화") { model.clearExcludedRecommendations() }.disabled(model.busy)
                            }
                        }
                    }.padding(.top, 8)
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
    private func recommendedRow(_ title: String, icon: String, detail: String, selected: Binding<Bool>, section: Section, mode: String? = nil, reason: String? = nil, review: [String] = []) -> some View {
        HStack(spacing: 12) {
            Toggle(title, isOn: selected).toggleStyle(DonyCheckbox()).labelsHidden().accessibilityLabel(title).disabled(model.busy || detail.hasPrefix("0개"))
            DonyIcon(icon).foregroundStyle(section.iconColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(14, weight: .medium))
                if let reason, !detail.hasPrefix("0개") { Text(reason).font(Theme.font(11)).foregroundStyle(Theme.secondary) }
            }
            Spacer()
            Text(detail).font(Theme.font(13)).foregroundStyle(Theme.secondary)
            Button("검토") { model.reviewSelection = review; open(section, mode: mode) }.buttonStyle(QuietButton()).disabled(model.busy || detail.hasPrefix("0개"))
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
