import SwiftUI
import AppKit
import CoreText
import DonyCore

enum Theme {
    static let ink = Color(hex: 0x191f28)
    static let body = Color(hex: 0x333d4b)
    static let sidebar = Color(hex: 0xf6f7f9)
    static let canvas = Color(hex: 0xf2f4f6)
    static let primary = Color(hex: 0x3182f6)
    static let blueWash = Color(hex: 0xe8f3ff)
    static let secondary = Color(hex: 0x6b7684)
    static let line = Color(hex: 0xe5e8eb)
    static let amber = Color(hex: 0xd98200)
    static let red = Color(hex: 0xf04452)
    static let success = Color(hex: 0x00a67d)
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("PretendardVariable-Regular", size: size).weight(weight)
    }
    static func registerFonts() {
        if let url = Bundle.main.url(forResource: "PretendardVariable", withExtension: "ttf", subdirectory: "Fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
struct DonyLogo: View {
    var size: CGFloat = 40
    var body: some View {
        if let url = Bundle.main.url(forResource: "DonyLogo", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22)).accessibilityLabel("dony 로고")
        }
    }
}

struct Panel: ViewModifier {
    let padding: CGFloat
    func body(content: Content) -> some View {
        content.padding(padding).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
extension View { func panel(_ padding: CGFloat = 28) -> some View { modifier(Panel(padding: padding)) } }

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.font(14, weight: .semibold)).padding(.horizontal, 16).frame(height: 42)
            .foregroundStyle(.white).background(enabled ? (configuration.isPressed ? Color(hex: 0x1b64da) : Theme.primary) : Color(hex: 0xb5d7ff))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.font(14, weight: .medium)).padding(.horizontal, 12).frame(height: 42)
            .foregroundStyle(enabled ? Theme.body : Theme.secondary.opacity(0.55)).background(configuration.isPressed ? Color(hex: 0xdfe4ea) : Color(hex: 0xe8ebef))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
struct Chip: View {
    let text: String
    var color: Color = Theme.primary
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(text).font(Theme.font(11, weight: .medium)) }
            .foregroundStyle(Theme.ink).padding(.horizontal, 10).padding(.vertical, 6).background(color.opacity(0.12)).clipShape(Capsule())
    }
}
struct PageHeader: View {
    let title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(28, weight: .bold)).tracking(-0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
    }
}
struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            DonyIcon(icon, size: 30).foregroundStyle(Theme.primary).frame(width: 66, height: 66).background(Theme.blueWash).clipShape(RoundedRectangle(cornerRadius: 19))
            Text(title).font(Theme.font(16, weight: .semibold))
            if !subtitle.isEmpty { Text(subtitle).font(Theme.font(12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 460) }
        }.frame(maxWidth: .infinity).padding(.vertical, 42).panel()
    }
}
struct ScanProgressView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let activity = model.activity {
            HStack(spacing: 15) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 5) {
                    Text(activity.title).font(Theme.font(13, weight: .semibold))
                    Text("\(activity.count)개 확인 · " + activity.detail).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(); Button("중단") { model.cancel() }.buttonStyle(QuietButton())
            }.panel(16)
        }
        if model.operationBusy {
            HStack(spacing: 12) { ProgressView().controlSize(.small); Text(model.operationLabel).font(Theme.font(12)); Spacer() }.panel(16)
        }
    }
}
struct IssuesView: View {
    let issues: [ScanIssue]
    var body: some View {
        if !issues.isEmpty {
            DisclosureGroup("건너뛴 항목 \(issues.count)개 · 권한 또는 상태 확인 필요") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(issue.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            Text(issue.message).font(Theme.font(11)).foregroundStyle(Theme.secondary)
                        }
                    }
                }.padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
            }.font(Theme.font(12)).tint(Theme.amber).panel(16)
        }
    }
}
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.primary
    var body: some View {
        GeometryReader { proxy in
            let points = values.enumerated().map { index, value in
                CGPoint(x: proxy.size.width * Double(index) / Double(max(1, values.count - 1)), y: proxy.size.height * (1 - min(100, max(0, value)) / 100))
            }
            Path { path in
                guard let first = points.first else { return }; path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }.stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }.frame(height: 36).accessibilityLabel("최근 사용량 그래프")
    }
}
struct MetricCard: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    var color: Color = Theme.primary
    var values: [Double] = []
    var progress: Double? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(title).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.secondary); Spacer(); DonyIcon(symbol).foregroundStyle(color) }
            Text(value).font(Theme.font(29, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if !values.isEmpty { Sparkline(values: values, color: color) }
            else if let progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.canvas)
                        Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, progress)))
                    }.frame(height: 5).frame(maxHeight: .infinity)
                }.frame(height: 36)
            } else { Color.clear.frame(height: 36) }
            Text(detail).font(Theme.font(12)).foregroundStyle(Theme.secondary).lineLimit(2).frame(minHeight: 28, alignment: .topLeading)
        }.frame(maxWidth: .infinity, alignment: .leading).panel(24)
    }
}

struct CandidateRow: View {
    @EnvironmentObject var model: AppModel
    let candidate: FileCandidate
    @Binding var selection: Set<String>
    var subtitle: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            Toggle("선택 " + candidate.name, isOn: Binding(get: { selection.contains(candidate.id) }, set: { if $0 { selection.insert(candidate.id) } else { selection.remove(candidate.id) } }))
                .toggleStyle(DonyCheckbox()).labelsHidden().disabled(model.busy).accessibilityLabel("선택 " + candidate.name)
            DonyIcon(candidate.fingerprint.isDirectory ? "folder.fill" : "doc.fill").font(Theme.font(19)).foregroundStyle(Theme.primary).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.name).font(Theme.font(12, weight: .medium)).lineLimit(1)
                Text(subtitle ?? candidate.url.path).font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle).help(candidate.url.path)
            }
            Spacer(minLength: 10)
            Text(DisplayFormat.bytes(candidate.bytes)).font(Theme.font(12, weight: .medium)).monospacedDigit().frame(width: 85, alignment: .trailing)
            Button { model.showFinder(candidate.url) } label: { DonyIcon("arrow.up.forward.square").foregroundStyle(Theme.secondary) }.buttonStyle(.plain).help("Finder에서 보기")
        }.padding(.vertical, 12).padding(.horizontal, 16)
    }
}
struct SelectionBar: View {
    @EnvironmentObject var model: AppModel
    let selected: [FileCandidate]
    let action: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(selected.count)개 선택 · \(DisplayFormat.bytes(selected.reduce(0) { $0 + $1.bytes }))").font(Theme.font(13, weight: .semibold))
                Text("휴지통 이동").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            }
            Spacer(); Button(action: action) { DonyLabel("휴지통으로 이동", icon: "trash") }.buttonStyle(PrimaryButton()).disabled(selected.isEmpty || model.busy)
        }.panel(16)
    }
}
