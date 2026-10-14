import SwiftUI
import DonyCore

/// 첫 설치 때 설정(권한·도구 연결)보다 먼저 보여주는 도니홈 소개.
struct IntroView: View {
    @EnvironmentObject var model: AppModel
    private struct Page { let icon: String; let color: Color; let title: String; let message: String }
    private let pages = [
        Page(icon: "sparkles", color: Color(hex: 0x25b79a), title: "검사 한 번이면 정리 추천까지", message: "캐시·로그, 중복 파일, 큰 파일을 찾아\n정리할 것만 체크해 드려요.\n정리한 파일은 휴지통으로 가서 언제든 되돌릴 수 있어요."),
        Page(icon: "gearshape.2", color: Color(hex: 0x8662ed), title: "개발 도구도 함께 챙겨요", message: "Codex, Claude, Cursor 같은 도구를 연동하면\n도구별 캐시와 메모리, 작업을 한눈에 보고\n안 쓰는 프로젝트의 빌드 파일을 정리해요."),
        Page(icon: "waveform.path.ecg", color: Color(hex: 0x4593fc), title: "Mac이 힘들면 먼저 알려드려요", message: "CPU·메모리·저장 공간이 부족해지면 알림으로 알려드려요.\n클립보드 기록과 배터리 관리도 함께 있어요."),
        Page(icon: "lock", color: Theme.success, title: "안전하게, 내 확인 아래에서만", message: "실행 중인 앱과 최근에 쓴 파일은 건드리지 않아요.\n정리하기 전에 항상 대상을 먼저 보여드려요.\n\n다음은 Mac 권한과 개발 도구 연결이에요.")
    ]
    /// 0쪽은 도니의 편지, 1쪽부터 기능 소개.
    private var page: Int { model.introPage ?? 0 }
    private var total: Int { pages.count + 1 }
    private var last: Bool { page == total - 1 }
    var body: some View {
        if page == 0 { LetterView(next: { withAnimation(.easeInOut(duration: 0.25)) { model.introPage = 1 } }) } else { featureBody }
    }
    private var featureBody: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); if !last { DonyTextAction(title: "건너뛰기") { model.introPage = nil } } }.frame(height: 42).padding(.horizontal, 24).padding(.top, 20)
            Spacer(minLength: 0)
            VStack(spacing: 28) {
                art(pages[page - 1])
                VStack(spacing: 14) {
                    Text(pages[page - 1].title).font(Theme.font(26, weight: .bold)).multilineTextAlignment(.center)
                    Text(pages[page - 1].message).font(Theme.font(15)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 48).id(page).transition(.opacity)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(0..<total, id: \.self) { index in Capsule().fill(index == page ? Theme.primary : Theme.line).frame(width: index == page ? 22 : 8, height: 8) }
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

/// 첫 화면: 도니가 이 앱을 만든 이유를 담은 편지. 줄이 하나씩 나타난다.
struct LetterView: View {
    var buttonTitle = "시작하기"
    let next: () -> Void
    @State private var shown = 0
    private let lines: [String] = [
        "도니입니다. 편지부터 읽고 가시죠.",
        "제 맥은 사양이 별로입니다. 그런데 작업은 8~9개씩 동시에 돌립니다. 이쯤 되면 맥은 난로가 되고, 팬은 이륙 준비를 하다가, 결국 멈춥니다. 사람은 멀쩡한데 맥이 먼저 쓰러져요.",
        "진짜 열받는 건 삘 받아서 한창 달릴 때 끊기는 겁니다. 흐름이 한 번 끊기면 그날 아이디어는 거기서 끝이에요.",
        "그래서 직접 만들었습니다. 정리는 c**m*맥처럼 시원하게, 복사 기록은 복붙러들이 사랑하는 Maccy처럼 빠르게, 맥 컨디션은 RunCat 고양이처럼 한눈에. 이 셋을 로컬에 맞게 하나로 묶었어요.",
        "코드는 전부 열어 뒀습니다. 가져다 쓰셔도 되고, 입맛대로 뜯어고치셔도 됩니다. 허락은 필요 없어요.",
        "맥도 사람도, 항상 행복하길."
    ]
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("맥이 난로가 되는 분들께").font(Theme.font(24, weight: .bold))
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line).font(Theme.font(14.5)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        .opacity(shown > index ? 1 : 0).offset(y: shown > index ? 0 : 8)
                }
                HStack(spacing: 10) {
                    Spacer()
                    Text("도니로부터").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.primary)
                    Image(nsImage: CodingCharacter.developerAvatar).resizable().interpolation(.none).frame(width: 34, height: 34)
                }.opacity(shown > lines.count ? 1 : 0).offset(y: shown > lines.count ? 0 : 8)
            }
            .padding(30).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white).clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
            .rotationEffect(.degrees(-0.6))
            Button(buttonTitle, action: next).buttonStyle(PrimaryButton()).opacity(shown > lines.count ? 1 : 0.35)
        }
        .padding(.horizontal, 36).padding(.vertical, 28).frame(width: 700, height: 620).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
        .task {
            for step in 1...(lines.count + 1) {
                try? await Task.sleep(nanoseconds: step == 1 ? 350_000_000 : 650_000_000)
                withAnimation(.easeOut(duration: 0.45)) { shown = step }
            }
        }
    }
}
