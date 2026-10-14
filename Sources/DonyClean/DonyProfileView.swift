import SwiftUI

struct DonyProfileView: View {
    @State private var letterShown = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("도니").font(Theme.font(28, weight: .bold))
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image(nsImage: CodingCharacter.developerAvatar)
                        .resizable().interpolation(.none).frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dony").font(Theme.font(22, weight: .bold))
                        Text("빠르게 만들고, 써보면서 더 나은 답을 찾아요.")
                            .font(Theme.font(14)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 12)
                    Link(destination: URL(string: "https://www.linkedin.com/in/donghun-kim94/")!) {
                        HStack(spacing: 7) { DonyIcon("linkedin", size: 18); Text("LinkedIn") }
                            .frame(width: Theme.actionWidth - 24)
                    }.buttonStyle(QuietButton()).help("Dony의 LinkedIn 프로필 열기")
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("안녕하세요, 도니예요.").font(Theme.font(16, weight: .semibold))
                    Text("지금은 닥터스코스메틱에서 이것저것 다 하는 잡부로 일하고 있어요. 제품을 만들고, 고객을 만나고, 팀이 더 편하게 일할 방법을 찾습니다.")
                    Text("마케팅에서 시작해 창업과 커머스 운영, 제품과 성장까지 두루 경험했어요. 생각은 빨리 만들어 써보고, 고객의 반응과 데이터로 다음 답을 찾는 편입니다.")
                }.font(Theme.font(14)).foregroundStyle(Theme.body).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }.panel()
            VStack(alignment: .leading, spacing: 12) {
                Text("도니홈을 만든 이유").font(Theme.font(16, weight: .semibold))
                Text("AI로 여러 작업을 동시에 돌리다 보면 Mac이 버거워지는 일이 많았어요. 개발 도구와 쌓여가는 로컬 작업물을 쉽게 관리하고 싶어서 도니홈을 만들고 있습니다.")
                    .font(Theme.font(14)).foregroundStyle(Theme.body).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).panel()
            VStack(alignment: .leading, spacing: 12) {
                Text("도니의 편지").font(Theme.font(16, weight: .semibold))
                Button { letterShown = true } label: {
                    HStack(spacing: 12) {
                        Chip(text: "공지", color: Theme.primary)
                        Text("맥이 난로가 되는 분들께").font(Theme.font(14, weight: .medium))
                        Spacer(minLength: 12)
                        Text("2026.10.14").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        DonyIcon("chevron.right", size: 12).foregroundStyle(Theme.secondary)
                    }.frame(height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("도니의 편지 열기")
            }.frame(maxWidth: .infinity, alignment: .leading).panel()
            .sheet(isPresented: $letterShown) { LetterView(buttonTitle: "닫기") { letterShown = false } }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
