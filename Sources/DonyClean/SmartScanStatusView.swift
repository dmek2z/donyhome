import SwiftUI
import DonyCore

struct SmartScanStatusView: View {
    @EnvironmentObject var model: AppModel
    private let phases: [SmartScanPhase] = [.cleanup, .development, .files, .applications, .space, .photos, .trash, .complete]
    private var scanning: Bool { model.activity?.title == "전체 검사" }
    private var phaseIndex: Int? { model.smartScanPhase.flatMap { phases.firstIndex(of: $0) } }
    private var completed: Bool { model.smart.map { !$0.cancelled } == true && !scanning }
    private var plan: RecommendedPlan? {
        guard let result = model.smart, !result.cancelled else { return nil }
        return RecommendedActions.plan(cleanup: result.recommended + result.developer.recommended, duplicates: result.duplicates.groups, preserving: result.similar.groups.map(\.original))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                DonyIcon(completed ? "checkmark" : "magnifyingglass", size: 28).foregroundStyle(Theme.primary).frame(width: 58, height: 58).background(Theme.blueWash).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) {
                    Text(heroTitle).font(Theme.font(22, weight: .semibold))
                    Text(heroDetail).font(Theme.font(12)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let plan { Text(DisplayFormat.bytes(plan.bytes)).font(Theme.font(28, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink) }
            }
            if scanning {
                // This is a phase indicator, not an estimate of elapsed scan work.
                HStack(spacing: 5) {
                    ForEach(Array(phases.dropLast().enumerated()), id: \.offset) { index, phase in
                        Capsule().fill(index <= (phaseIndex ?? -1) ? Theme.primary : Theme.line).frame(height: 5)
                            .help(phaseTitle(phase)).accessibilityLabel(phaseTitle(phase) + (index < (phaseIndex ?? -1) ? " 확인 완료" : index == phaseIndex ? " 검사 중" : " 대기"))
                    }
                }.accessibilityElement(children: .combine)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    summary(0, title: "캐시 · 로그", icon: "sparkles").frame(minWidth: 170)
                    Divider().frame(height: 94)
                    summary(1, title: "개발", icon: "gearshape").frame(minWidth: 170)
                    Divider().frame(height: 94)
                    summary(2, title: "파일 · 앱", icon: "folder").frame(minWidth: 170)
                }
                VStack(alignment: .leading, spacing: 16) {
                    summary(0, title: "캐시 · 로그", icon: "sparkles")
                    Divider()
                    summary(1, title: "개발", icon: "gearshape")
                    Divider()
                    summary(2, title: "파일 · 앱", icon: "folder")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private var heroTitle: String {
        if scanning { return "Mac을 확인하고 있어요" }
        if model.smart?.cancelled == true { return "검사를 중단했어요" }
        if completed { return "정리할 항목을 확인했어요" }
        return "전체 검사" 
    }
    private var heroDetail: String {
        if scanning { return model.smartScanPhase.map(phaseTitle) ?? "검사 준비 중" }
        if let result = model.smart, result.cancelled { return "일부 결과만 표시해요. 정리 추천은 다시 검사한 뒤 확인해 주세요." }
        if let plan {
            if let result = model.smart, !result.issues.isEmpty { return "정리 추천 \(plan.items.count)개 · 확인이 필요한 경로 \(Set(result.issues.map(\.path)).count)개" }
            return "정리 추천 \(plan.items.count)개 · 실제 정리 전 항목을 검토해 주세요."
        }
        return "캐시·개발 생성물·파일·앱을 확인해요."
    }
    private func summary(_ group: Int, title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { DonyIcon(icon, size: 17).foregroundStyle(Theme.primary); Text(title).font(Theme.font(14, weight: .semibold)); Spacer(minLength: 8); Text(groupStatus(group)).font(Theme.font(11)).foregroundStyle(Theme.secondary) }
            Text(groupDetail(group)).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.body).lineLimit(2)
            Text(groupFootnote(group)).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func groupStatus(_ group: Int) -> String {
        if completed { return "확인 완료" }
        guard scanning || model.smart?.cancelled == true, let index = phaseIndex else { return "대기" }
        let first = group, last = group == 2 ? 6 : group
        if index < first { return "대기" }
        if index > last { return "확인 완료" }
        return scanning ? "검사 중" : model.smart?.cancelled == true ? "검사 중단" : "대기"
    }
    private func groupDetail(_ group: Int) -> String {
        guard !scanning, let result = model.smart else { return groupStatus(group) == "대기" ? "아직 확인하지 않았어요" : "결과를 확인하고 있어요" }
        if result.cancelled {
            guard groupStatus(group) != "대기" else { return "아직 확인하지 않았어요" }
            let count = group == 0 ? result.cleanup.items.count : group == 1 ? result.developer.items.count : result.largeFiles.items.count
            return "확인한 항목 \(count)개 · 일부 결과"
        }
        let retained = result.similar.groups.map(\.original)
        let items: [FileCandidate]
        if group == 0 { items = RecommendedActions.plan(cleanup: result.recommended, duplicates: result.duplicates.groups, includeCopies: false, preserving: retained).items }
        else if group == 1 { items = RecommendedActions.plan(cleanup: result.developer.recommended, duplicates: result.duplicates.groups, includeCopies: false, preserving: retained).items }
        else { items = RecommendedActions.plan(cleanup: [], duplicates: result.duplicates.groups, preserving: retained).items }
        return "추천 \(items.count)개 · " + DisplayFormat.bytes(items.reduce(0) { $0 + $1.bytes })
    }
    private func groupFootnote(_ group: Int) -> String {
        if scanning { return group == 0 ? "오래된 캐시·로그 확인" : group == 1 ? "다시 생성 가능한 개발 캐시 확인" : "중복·큰 파일·앱·사진·휴지통 확인" }
        guard let result = model.smart else { return "검사 후 실제 결과를 표시해요" }
        if result.cancelled, groupStatus(group) == "대기" { return "중단되어 확인하지 못했어요" }
        if group == 0 { return "확인한 캐시·로그 \(result.cleanup.items.count)개" }
        if group == 1 { return "확인한 개발 생성물 \(result.developer.items.count)개" }
        if result.cancelled, (phaseIndex ?? -1) < 3 { return "큰 파일 일부 결과 · 설치 앱 미확인" }
        if result.cancelled, phaseIndex == 3 { return "큰 파일 \(result.largeFiles.items.count)개 · 설치 앱 일부 결과" }
        return "큰 파일 \(result.largeFiles.items.count)개 · 설치 앱 \(result.applications.apps.count)개"
    }
    private func phaseTitle(_ phase: SmartScanPhase) -> String {
        switch phase {
        case .cleanup: return "캐시 · 로그 확인"
        case .development: return "개발 캐시 확인"
        case .files: return "오래된 파일 · 큰 파일 · 중복 확인"
        case .applications: return "설치 앱 · 남은 앱 파일 확인"
        case .space: return "폴더 용량 확인"
        case .photos: return "유사 사진 확인"
        case .trash: return "휴지통 확인"
        case .complete: return "검사 완료"
        }
    }
}
