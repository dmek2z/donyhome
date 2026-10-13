import SwiftUI

struct DonyProfileView: View {
    private let career: [(String, String)] = [
        ("2026–", "닥터스코스메틱 · 최고전략책임자(CSO)"),
        ("2025–2026", "그린리본 · Product Owner / Marketing Lead"),
        ("2023–2025", "테드스토리 · 사업총괄이사(COO)"),
        ("2022–2023", "포티파이 · 마케팅 및 사업개발팀 리드"),
        ("2019", "넥스트벨류 창업 · 이커머스 분석·광고 자동화")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("도니").font(Theme.font(28, weight: .bold))
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image(nsImage: CodingCharacter.developerAvatar)
                        .resizable().interpolation(.none).frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("김동훈 · Dony").font(Theme.font(22, weight: .bold))
                        Text("빠르게 만들고, 써보면서 더 나은 답을 찾아요.")
                            .font(Theme.font(14)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 12)
                    Link(destination: URL(string: "https://www.linkedin.com/in/donghun-kim94/")!) {
                        HStack(spacing: 7) { DonyIcon("linkedin", size: 18); Text("LinkedIn") }
                            .frame(width: Theme.actionWidth - 24)
                    }.buttonStyle(QuietButton()).help("김동훈의 LinkedIn 프로필 열기")
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
                Text("지나온 일들").font(Theme.font(16, weight: .semibold))
                VStack(spacing: 0) {
                    ForEach(Array(career.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 16) {
                            Text(entry.0).font(Theme.font(12)).foregroundStyle(Theme.secondary)
                                .frame(width: 88, alignment: .leading)
                            Text(entry.1).font(Theme.font(14)).foregroundStyle(Theme.body)
                                .lineLimit(1).truncationMode(.middle).help(entry.1)
                            Spacer(minLength: 0)
                        }.frame(height: Theme.listRowHeight)
                        if index < career.count - 1 { Divider() }
                    }
                }.padding(.horizontal, 24).panel(0)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
