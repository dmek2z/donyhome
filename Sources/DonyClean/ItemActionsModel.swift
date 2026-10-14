import Foundation
import DonyCore

extension AppModel {
    func excludeFromRecommendations(_ candidate: FileCandidate) {
        excludedRecommendations.insert(candidate.id)
        selectionExcluded(candidate.id)
        banner = candidate.name + "은(는) 앞으로 추천에서 빼요. 직접 선택하면 정리할 수 있어요."
    }
    func restoreRecommendation(_ candidate: FileCandidate) {
        excludedRecommendations.remove(candidate.id)
        banner = candidate.name + "을(를) 다시 추천 대상에 넣었어요."
    }
    func clearExcludedRecommendations() { excludedRecommendations.removeAll(); banner = "추천 제외 목록을 비웠어요." }
    /// 추천에서 막 뺀 항목이 미리 선택돼 있던 경우를 위해 검토 선택에서도 뺀다.
    private func selectionExcluded(_ id: String) { reviewSelection.removeAll { $0 == id } }
    /// macOS 빠른 보기. 일반 파일만 열고 폴더는 Finder로 안내한다.
    func quickLook(_ candidate: FileCandidate) {
        guard candidate.fingerprint.isRegular, FileManager.default.fileExists(atPath: candidate.url.path) else { showFinder(candidate.url); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", candidate.url.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { banner = "미리보기를 열지 못했어요. Finder에서 확인해 주세요." }
    }
}
