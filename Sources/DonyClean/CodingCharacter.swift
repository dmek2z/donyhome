import AppKit
import SwiftUI
import DonyCore

@MainActor enum CodingCharacter {
    // MenuBarExtra extracts native images; the image itself must have menu-bar dimensions.
    private static let colorFrames = frames(mode: .color)
    private static let grayscaleFrames = frames(mode: .monochrome)
    static func image(mode: CharacterMode, activity: CharacterActivity, frame: Int) -> NSImage {
        let offset = activity == .relaxed ? 0 : 4
        return (mode == .color ? colorFrames : grayscaleFrames)[offset + frame % 4]
    }
    private static func frames(mode: CharacterMode) -> [NSImage] { (0..<8).map { index in
        let pose = index % 4
        let relaxed = index < 4
        let rows = ["    hhhhh         ", "   hhhhhhh        ", "   hsssssh        ", "   sskssks        ", "    sssss         ", "    bbbbb  kkkkkk ", "   bbbbbbb kmggmk ", pose % 2 == 0 ? "   bbssbbb kmmgmk " : "   bbbssbb kmggmk ", pose % 2 == 0 ? "     s ss  kkkkkk " : "    ss s   kkkkkk ", "  mmmmmmmmmmmkkmmm", "  kkkkkkkkkkkkkkkk", "    kk  kk        "]
        var pixels = Array(repeating: Array(repeating: Character(" "), count: 18), count: 12)
        for (y, row) in rows.enumerated() { for (x, value) in row.prefix(18).enumerated() { pixels[y][x] = value } }
        func put(_ x: Int, _ y: Int, _ value: Character) { pixels[y][x] = value }
        if relaxed {
            if pose < 2 {
                // Mug on the desk, with alternating steam while typing slowly.
                put(0, 7, "r"); put(1, 7, "r"); put(0, 8, "c"); put(1, 8, "c"); put(2, 7, "c")
                put(pose, 5, "m"); put(1 - pose, 6, "m")
            } else {
                // Raise the mug to the mouth; the other hand stays on the keyboard.
                put(1, 4, "r"); put(2, 4, "r"); put(1, 5, "c"); put(2, 5, "c"); put(0, 4, "c")
                put(2, 6, "s"); put(3, 6, "s"); put(3, 5, "s"); put(4, 5, "s")
                put(4, 7, "b"); put(5, 7, "b"); put(5, 8, " ")
                put(0, pose == 2 ? 2 : 3, "m")
            }
        } else {
            // Drops move downward next to the face; both hands alternate rapidly.
            put(9, 2 + pose % 3, "w"); put(9, 3 + pose % 3, "w")
            put(1, 3 + pose % 2, "w")
            put(10, pose % 2 == 0 ? 7 : 8, "m")
            put(12 + pose, 6, "g")
        }
        let colors: [Character: NSColor] = ["h": NSColor(red: 0.25, green: 0.18, blue: 0.38, alpha: 1), "s": NSColor(red: 1, green: 0.76, blue: 0.55, alpha: 1), "b": NSColor(red: 0.25, green: 0.53, blue: 1, alpha: 1), "k": NSColor(red: 0.12, green: 0.18, blue: 0.29, alpha: 1), "m": NSColor(red: 0.62, green: 0.76, blue: 0.91, alpha: 1), "g": NSColor(red: 0.32, green: 0.96, blue: 0.69, alpha: 1), "c": NSColor(white: 0.95, alpha: 1), "r": NSColor(red: 0.49, green: 0.28, blue: 0.14, alpha: 1), "w": NSColor(red: 0.12, green: 0.78, blue: 1, alpha: 1)]
        let image = NSImage(size: NSSize(width: 27, height: 18), flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .none
            NSGraphicsContext.current?.shouldAntialias = false
            for (y, row) in pixels.enumerated() { for (x, char) in row.enumerated() {
                if let color = colors[char], let rgb = color.usingColorSpace(.deviceRGB) {
                    let gray = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
                    (mode == .monochrome ? NSColor(white: gray, alpha: 1) : color).setFill()
                    NSRect(x: CGFloat(x) * 1.5, y: CGFloat(11 - y) * 1.5, width: 1.5, height: 1.5).fill()
                }
            } }
            return true
        }
        image.isTemplate = false
        return image
    } }

    static let developerAvatar: NSImage = {
        let rows = ["    hhhhhh    ", "   hhhhhhhh   ", "   hssssssh   ", "  skkksskkks  ", "  skskkksks   ", "   kkksskkk   ", "    sssss     ", "    ssssss    ", "   bbbbbbbb   ", "  bbbggbbbb   ", "  bbbbbbbbb   ", "   bb  bb     ", "   kk  kk     ", "              "]
        let colors: [Character: NSColor] = ["h": NSColor(white: 0.25, alpha: 1), "s": NSColor(red: 1, green: 0.76, blue: 0.55, alpha: 1), "k": NSColor(red: 0.15, green: 0.21, blue: 0.3, alpha: 1), "b": NSColor(red: 0.53, green: 0.39, blue: 0.93, alpha: 1), "g": NSColor(red: 0.35, green: 0.9, blue: 0.75, alpha: 1)]
        return NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = false
            for (y, row) in rows.enumerated() { for (x, char) in row.enumerated() {
                if let color = colors[char] { color.setFill(); NSRect(x: CGFloat(x) * 20 / 14, y: CGFloat(13 - y) * 20 / 14, width: 20 / 14, height: 20 / 14).fill() }
            } }
            return true
        }
    }()
}

@MainActor final class CodingCharacterAnimator: ObservableObject {
    @Published var image: NSImage
    var mode: CharacterMode { didSet { frame = -1; tick() } }
    private var timer: Timer?
    private var activity: CharacterActivity = .relaxed
    private var frame = -1
    init(mode: CharacterMode) {
        self.mode = mode; image = CodingCharacter.image(mode: mode, activity: .relaxed, frame: 0)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func update(cpu: Double?, pressure: MemoryPressure) {
        let next = CharacterActivity.resolve(cpu: cpu, pressure: pressure)
        if next != activity { activity = next; frame = -1 }
        tick()
    }
    private func tick() {
        let next = Int(Date().timeIntervalSince1970 / activity.interval) % 4
        guard next != frame else { return }; frame = next
        image = CodingCharacter.image(mode: mode, activity: activity, frame: next)
    }
}
struct CodingCharacterLabel: View {
    @ObservedObject var animator: CodingCharacterAnimator
    var body: some View { Image(nsImage: animator.image).renderingMode(.original).accessibilityLabel("코딩하는 dony") }
}

struct CharacterPreviewView: View {
    let mode: CharacterMode
    var body: some View {
        HStack(spacing: 12) {
            preview("여유 (커피 한 잔)", activity: .relaxed)
            preview("과부하 (땀 뻘뻘)", activity: .overloaded)
        }
    }
    private func preview(_ title: String, activity: CharacterActivity) -> some View {
        VStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: activity.interval)) { context in
                let frame = Int(context.date.timeIntervalSince1970 / activity.interval) % 4
                Image(nsImage: CodingCharacter.image(mode: mode, activity: activity, frame: frame))
                    .resizable().interpolation(.none).scaledToFit().frame(width: 108, height: 72)
            }.frame(height: 88)
            Text(title).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity).padding(12).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
