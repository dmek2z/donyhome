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
            HStack {
                DonyIcon("sparkles", size: 24).foregroundStyle(Theme.success)
                Text("스마트 정리").font(Theme.font(18, weight: .semibold))
                Spacer()
                if let date = model.smartDate { Text(date, style: .time).font(Theme.font(12)).foregroundStyle(Theme.secondary) }
            }
            HStack(spacing: 8) {
                Text("파일 검사 범위").foregroundStyle(Theme.secondary)
                Text(model.folder.path).lineLimit(1).truncationMode(.middle).help(model.folder.path)
                Spacer(); Button("폴더 선택") { model.chooseFolder() }.buttonStyle(QuietButton()).disabled(model.busy)
            }.font(Theme.font(12))
            if let smart = model.smart {
                if smart.cancelled { Chip(text: "중단됨 · 다시 점검해 주세요", color: Theme.amber) }
                VStack(spacing: 0) {
                    recommendedRow("오래된 캐시 · 로그", icon: "sparkles", detail: "\(model.recommendedCleanup.count)개 · " + DisplayFormat.bytes(model.recommendedCleanup.reduce(0) { $0 + $1.bytes }), selected: $cleanCaches, section: .cleanup, mode: "캐시 · 로그")
                    Divider()
                    recommendedRow("동일한 파일 사본", icon: "doc.on.doc", detail: "\(model.recommendedDuplicateCopies.count)개 · " + DisplayFormat.bytes(model.recommendedDuplicateCopies.reduce(0) { $0 + $1.bytes }), selected: $cleanCopies, section: .files, mode: "중복 파일")
                    Divider()
                    recommendedRow("개발 캐시", icon: "gearshape", detail: "\(model.recommendedDeveloper.count)개 · " + DisplayFormat.bytes(model.recommendedDeveloper.reduce(0) { $0 + $1.bytes }), selected: $cleanDeveloper, section: .cleanup, mode: "개발 캐시")
                    Divider()
                    reviewRow("큰 파일", icon: "folder", detail: "\(model.largeFiles.items.count)개 · " + DisplayFormat.bytes(model.largeFiles.totalBytes), section: .files, mode: "큰 파일")
                    Divider()
                    reviewRow("오래된 파일 · 설치 파일", icon: "doc.fill", detail: "\(model.clutter.oldFiles.items.count)개 · \(model.clutter.installers.items.count)개", section: .files, mode: "오래된 파일")
                    Divider()
                    reviewRow("유사 사진 후보", icon: "doc.fill", detail: "\(model.similar.groups.count)개 그룹", section: .files, mode: "유사 사진")
                    Divider()
                    reviewRow("앱 잔여물 후보", icon: "square.stack.3d.up", detail: "\(model.leftovers.items.count)개", section: .applications, mode: "잔여물 후보")
                    Divider()
                    reviewRow("폴더 용량 지도", icon: "externaldrive", detail: DisplayFormat.bytes(model.spaceMap.totalBytes), section: .space)
                    Divider()
                    reviewRow("휴지통", icon: "trash", detail: "\(model.trashItems.items.count)개 · " + DisplayFormat.bytes(model.trashItems.totalBytes), section: .tools)
                    Divider()
                    reviewRow("설치 앱", icon: "square.stack.3d.up", detail: "\(model.applications.apps.count)개", section: .applications, mode: "설치 앱")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(selectedCount)개 추천 · " + DisplayFormat.bytes(selectedBytes)).font(Theme.font(21, weight: .semibold))
                        Text("원본은 보관하고 사본은 휴지통으로 이동해요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("추천 정리 실행") { model.runRecommended(includeCleanup: cleanCaches, includeDuplicates: cleanCopies, includeDeveloper: cleanDeveloper) }.buttonStyle(PrimaryButton()).disabled(model.busy || smart.cancelled || selectedCount == 0)
                }.padding(.top, 8)
                DisclosureGroup("추천 기준") {
                    Text("개발 캐시: 7일 이상 변경 없고 관련 도구가 종료된 생성물. 캐시: 확인된 앱 8종 중 14일 이상 변경이 없는 항목. 로그: 30일 이상 지난 .log 및 회전 로그. 실행 중인 앱·최근 변경·링크가 포함된 항목은 제외합니다. 중복은 내용이 같은 파일만 추리며 원본 한 개를 남깁니다.").font(Theme.font(12)).foregroundStyle(Theme.secondary).padding(.top, 8)
                }.font(Theme.font(12)).tint(Theme.secondary)
                if !smart.issues.isEmpty { Text("확인하지 못한 항목 \(smart.issues.count)개 · 각 결과에서 확인").font(Theme.font(12)).foregroundStyle(Theme.amber) }
            } else {
                HStack {
                    Text("캐시 · 생성물 · 중복 · 오래된 파일 · 잔여물 · 용량을 함께 확인해요.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                    Spacer()
                }.padding(.vertical, 8)
            }
        }.panel()
    }
    private func open(_ section: Section, mode: String?) {
        if let mode {
            switch section { case .cleanup: model.cleanupMode = mode; case .files: model.filesMode = mode; case .applications: model.applicationsMode = mode; default: break }
        }
        model.section = section
    }
    private func recommendedRow(_ title: String, icon: String, detail: String, selected: Binding<Bool>, section: Section, mode: String? = nil) -> some View {
        HStack(spacing: 12) {
            Toggle(title, isOn: selected).toggleStyle(DonyCheckbox()).labelsHidden().accessibilityLabel(title).disabled(model.busy)
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
