import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    private let credits: [(String, String, String, String)] = [
        ("battery", "Mentor Palokaj · MIT", "https://github.com/actuallymentor/battery", "Battery/LICENSE.battery"),
        ("Maccy", "Alex Rodionov · MIT", "https://github.com/p0deje/Maccy", "Clipboard/Maccy-LICENSE.txt"),
        ("SMC", "smcFanControl · GPLv2", "https://github.com/hholtmann/smcFanControl", "Battery/LICENSE.smc"),
        ("Fuse", "krisk · MIT", "https://github.com/krisk/fuse-swift", "Clipboard/Fuse-LICENSE.txt"),
        ("Phosphor Icons", "MIT", "https://github.com/phosphor-icons/core", "Icons/LICENSE"),
        ("Pretendard", "SIL Open Font License", "https://github.com/orioncactus/pretendard", "Fonts/OFL.txt")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("도니홈 정보").font(Theme.font(22, weight: .bold)); Spacer(); Button("완료") { dismiss() }.buttonStyle(QuietButton()) }
            Text("donyhome " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0")).font(Theme.font(16, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(credits, id: \.0) { name, credit, website, path in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(name).font(Theme.font(16, weight: .semibold)); Spacer(); Link("원본", destination: URL(string: website)!).font(Theme.font(12)).foregroundStyle(Theme.primary) }
                            Text(credit).font(Theme.font(12)).foregroundStyle(Theme.secondary)
                            DisclosureGroup("라이선스") {
                                Text(license(path)).font(.system(size: 10)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }.font(Theme.font(12)).tint(Theme.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).panel(20)
                    }
                }
            }
        }.padding(24).frame(width: 560, height: 620).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
    }
    private func license(_ path: String) -> String {
        guard let root = Bundle.main.resourceURL else { return "라이선스 파일을 찾지 못했습니다." }
        return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "라이선스 파일을 찾지 못했습니다."
    }
}
