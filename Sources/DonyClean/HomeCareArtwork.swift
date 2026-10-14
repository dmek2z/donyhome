import SwiftUI
import DonyCore

/// A friendly Mac and the app's existing pixel coder, drawn entirely on device.
struct HomeCareArtwork: View {
    var activity: CharacterActivity = .relaxed
    var mode: CharacterMode = .color
    private var working: Bool { activity != .relaxed }
    var body: some View {
        ZStack {
            Ellipse().fill(Theme.blueWash).frame(width: 320, height: 124).offset(y: 45)
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color.white)
                    RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 11).fill(Theme.blueWash).padding(10).padding(.bottom, 14)
                    VStack(spacing: 13) {
                        HStack(spacing: 48) {
                            Capsule().fill(Theme.body).frame(width: 9, height: working ? 9 : 14)
                            Capsule().fill(Theme.body).frame(width: 9, height: working ? 9 : 14)
                        }
                        HomeMacSmile().stroke(Theme.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 36, height: 13)
                    }.offset(y: -6)
                    Circle().fill(Theme.line).frame(width: 5, height: 5).offset(y: 66)
                }.frame(width: 226, height: 156)
                Rectangle().fill(Theme.line).frame(width: 32, height: 20)
                RoundedRectangle(cornerRadius: 5).fill(Color.white).overlay { RoundedRectangle(cornerRadius: 5).stroke(Theme.line, lineWidth: 1) }.frame(width: 86, height: 10)
            }.offset(x: -12, y: -4)
            TimelineView(.animation(minimumInterval: activity.interval, paused: false)) { context in
                let frame = Int(context.date.timeIntervalSince1970 / activity.interval) % 4
                Image(nsImage: CodingCharacter.image(mode: mode, activity: activity, frame: frame))
                    .resizable().interpolation(.none).scaledToFit().frame(width: 108, height: 72)
            }.offset(x: 111, y: 61)
            DonyIcon("sparkles", size: 22).foregroundStyle(Theme.primary.opacity(0.65)).offset(x: -145, y: -62)
            Circle().fill(Theme.primary.opacity(0.18)).frame(width: 8, height: 8).offset(x: 136, y: -57)
        }.frame(width: 340, height: 216)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(working ? "Mac을 살펴보는 도니" : "웃는 Mac과 코딩하는 도니")
    }
}
private struct HomeMacSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.7))
        return path
    }
}
