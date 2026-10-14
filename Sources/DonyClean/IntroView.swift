import SwiftUI
import DonyCore

/// 첫 설치 때 설정(권한·도구 연결)보다 먼저 보여주는 도니홈 소개.
struct IntroView: View {
    @EnvironmentObject var model: AppModel
    private struct Page { let icon: String; let color: Color; let title: String; let message: String }
    private let pages = [
        Page(icon: "", color: Theme.primary, title: "도니홈에 오신 걸 환영해요", message: "Mac을 가볍게 유지하고\n개발 환경까지 한 번에 챙겨요."),
        Page(icon: "sparkles", color: Color(hex: 0x25b79a), title: "검사 한 번이면 정리 추천까지", message: "캐시·로그, 중복 파일, 큰 파일을 찾아\n정리할 것만 체크해 드려요.\n정리한 파일은 휴지통으로 가서 언제든 되돌릴 수 있어요."),
        Page(icon: "gearshape.2", color: Color(hex: 0x8662ed), title: "개발 도구도 함께 챙겨요", message: "Codex, Claude, Cursor 같은 도구를 연동하면\n도구별 캐시와 메모리, 작업을 한눈에 보고\n안 쓰는 프로젝트의 빌드 파일을 정리해요."),
        Page(icon: "waveform.path.ecg", color: Color(hex: 0x4593fc), title: "Mac이 힘들면 먼저 알려드려요", message: "CPU·메모리·저장 공간이 부족해지면 알림으로 알려드려요.\n클립보드 기록과 배터리 관리도 함께 있어요."),
        Page(icon: "lock", color: Theme.success, title: "안전하게, 내 확인 아래에서만", message: "실행 중인 앱과 최근에 쓴 파일은 건드리지 않아요.\n정리하기 전에 항상 대상을 먼저 보여드려요.\n\n다음은 Mac 권한과 개발 도구 연결이에요.")
    ]
    private var page: Int { model.introPage ?? 0 }
    private var last: Bool { page == pages.count - 1 }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); if !last { DonyTextAction(title: "건너뛰기") { model.introPage = nil } } }.frame(height: 42).padding(.horizontal, 24).padding(.top, 20)
            Spacer(minLength: 0)
            VStack(spacing: 28) {
                art(pages[page])
                VStack(spacing: 14) {
                    Text(pages[page].title).font(Theme.font(26, weight: .bold)).multilineTextAlignment(.center)
                    Text(pages[page].message).font(Theme.font(15)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 48).id(page).transition(.opacity)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in Capsule().fill(index == page ? Theme.primary : Theme.line).frame(width: index == page ? 22 : 8, height: 8) }
            }.padding(.bottom, 24)
            Button(last ? "설정 시작" : "다음") { withAnimation(.easeInOut(duration: 0.2)) { model.introPage = last ? nil : page + 1 } }
                .buttonStyle(PrimaryButton()).padding(.horizontal, 24).padding(.bottom, 24)
        }.frame(width: 700, height: 620).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
    }
    @ViewBuilder private func art(_ page: Page) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32).fill(page.color.opacity(0.12)).frame(width: 132, height: 132)
            if page.icon.isEmpty { Image(nsImage: CodingCharacter.developerAvatar).resizable().interpolation(.none).frame(width: 84, height: 84) }
            else { DonyIcon(page.icon, size: 60).foregroundStyle(page.color) }
        }
    }
}
