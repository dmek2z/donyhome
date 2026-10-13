import SwiftUI
import DonyCore

struct SmartCareView: View {
    @EnvironmentObject var model: AppModel
    @State private var cleanCaches = true
    @State private var cleanCopies = true
    private var plan: RecommendedPlan { model.recommendedPlan(includeCleanup: cleanCaches, includeDuplicates: cleanCopies) }
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
                    recommendedRow("오래된 캐시 · 로그", icon: "sparkles", detail: "\(model.recommendedCleanup.count)개 · " + DisplayFormat.bytes(model.recommendedCleanup.reduce(0) { $0 + $1.bytes }), selected: $cleanCaches, section: .cleanup)
                    Divider()
                    recommendedRow("동일한 파일 사본", icon: "doc.on.doc", detail: "\(model.duplicateCopies.count)개 · " + DisplayFormat.bytes(model.duplicateCopies.reduce(0) { $0 + $1.bytes }), selected: $cleanCopies, section: .files)
                    Divider()
                    reviewRow("큰 파일", icon: "folder", detail: "\(model.largeFiles.items.count)개 · " + DisplayFormat.bytes(model.largeFiles.totalBytes), section: .files)
                    Divider()
                    reviewRow("설치 앱", icon: "square.stack.3d.up", detail: "\(model.applications.apps.count)개", section: .applications)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(selectedCount)개 추천 · " + DisplayFormat.bytes(selectedBytes)).font(Theme.font(21, weight: .semibold))
                        Text("원본은 보관하고 사본은 휴지통으로 이동해요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("추천 정리 실행") { model.runRecommended(includeCleanup: cleanCaches, includeDuplicates: cleanCopies) }.buttonStyle(PrimaryButton()).disabled(model.busy || smart.cancelled || selectedCount == 0)
                }.padding(.top, 8)
                DisclosureGroup("추천 기준") {
                    Text("캐시: 확인된 앱 8종 중 14일 이상 변경이 없는 항목. 로그: 30일 이상 지난 .log 및 회전 로그. 실행 중인 앱·최근 변경·링크가 포함된 항목은 제외합니다. 중복은 내용이 같은 파일만 추리며 원본 한 개를 남깁니다.").font(Theme.font(12)).foregroundStyle(Theme.secondary).padding(.top, 8)
                }.font(Theme.font(12)).tint(Theme.secondary)
                if !smart.issues.isEmpty { Text("확인하지 못한 항목 \(smart.issues.count)개 · 각 결과에서 확인").font(Theme.font(12)).foregroundStyle(Theme.amber) }
            } else {
                HStack {
                    Text("캐시 · 로그 · 큰 파일 · 중복 · 설치 앱을 한 번에 확인해요.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                    Spacer()
                }.padding(.vertical, 8)
            }
        }.panel()
    }
    private func recommendedRow(_ title: String, icon: String, detail: String, selected: Binding<Bool>, section: Section) -> some View {
        HStack(spacing: 12) {
            Toggle(title, isOn: selected).toggleStyle(DonyCheckbox()).labelsHidden().accessibilityLabel(title).disabled(model.busy)
            DonyIcon(icon).foregroundStyle(section.iconColor)
            Text(title).font(Theme.font(14, weight: .medium)); Spacer()
            Text(detail).font(Theme.font(13)).foregroundStyle(Theme.secondary)
            Button("검토") { model.section = section }.buttonStyle(QuietButton()).disabled(model.busy)
        }.padding(.vertical, 10)
    }
    private func reviewRow(_ title: String, icon: String, detail: String, section: Section) -> some View {
        HStack(spacing: 12) {
            DonyIcon(icon).foregroundStyle(section.iconColor).padding(.leading, 32)
            Text(title).font(Theme.font(14, weight: .medium)); Spacer()
            Text(detail).font(Theme.font(13)).foregroundStyle(Theme.secondary)
            Button("직접 선택") { model.section = section }.buttonStyle(QuietButton()).disabled(model.busy)
        }.padding(.vertical, 10)
    }
}
