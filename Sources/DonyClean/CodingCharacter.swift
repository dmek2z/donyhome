import AppKit
import SwiftUI
import DonyCore

@MainActor enum CodingCharacter {
    // MenuBarExtra extracts native images; the image itself must have menu-bar dimensions.
    static let images = frames(mode: .color)
    static let monochromeImages = frames(mode: .monochrome)
    static func frames(mode: CharacterMode) -> [NSImage] { (0..<4).map { index in
        let frame = index % 2
        let rows = ["    hhhhh         ", "   hhhhhhh        ", "   hsssssh        ", "   sskssks        ", "    sssss         ", "    bbbbb  kkkkkk ", "   bbbbbbb kmggmk ", frame == 0 ? "   bbssbbb kmmgmk " : "   bbbssbb kmggmk ", frame == 0 ? "     s ss  kkkkkk " : "    ss s   kkkkkk ", "  mmmmmmmmmmmkkmmm", "  kkkkkkkkkkkkkkkk", "    kk  kk        "]
        let colors: [Character: NSColor] = ["h": NSColor(red: 0.25, green: 0.18, blue: 0.38, alpha: 1), "s": NSColor(red: 1, green: 0.76, blue: 0.55, alpha: 1), "b": NSColor(red: 0.25, green: 0.53, blue: 1, alpha: 1), "k": NSColor(red: 0.12, green: 0.18, blue: 0.29, alpha: 1), "m": NSColor(red: 0.62, green: 0.76, blue: 0.91, alpha: 1), "g": NSColor(red: 0.32, green: 0.96, blue: 0.69, alpha: 1)]
        let image = NSImage(size: NSSize(width: 27, height: 18), flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .none
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() {
                    if let color = colors[char] {
                        let rgb = color.usingColorSpace(.deviceRGB)!
                        let gray = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
                        (mode == .monochrome ? NSColor(white: gray, alpha: 1) : color).setFill(); NSRect(x: CGFloat(x) * 1.5, y: CGFloat(11 - y) * 1.5, width: 1.5, height: 1.5).fill() }
                }
            }
            if index >= 2 { (mode == .monochrome ? NSColor(white: 0.8, alpha: 1) : NSColor.cyan).setFill(); NSRect(x: frame == 0 ? 3 : 24, y: 12, width: 1.5, height: 3).fill() }
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
    private var interval = 0.65
    private var frame = -1
    init(mode: CharacterMode) {
        self.mode = mode; image = mode == .color ? CodingCharacter.images[0] : CodingCharacter.monochromeImages[0]
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func update(cpu: Double?, pressure: MemoryPressure) {
        interval = pressure == .critical || (cpu ?? 0) >= 85 ? 0.10 : pressure == .warning || (cpu ?? 0) >= 50 ? 0.22 : 0.65
        tick()
    }
    private func tick() {
        let next = Int(Date().timeIntervalSince1970 / interval) % 2 + (interval <= 0.22 ? 2 : 0)
        guard next != frame else { return }; frame = next
        image = mode == .color ? CodingCharacter.images[next] : CodingCharacter.monochromeImages[next]
    }
}
struct CodingCharacterLabel: View {
    @ObservedObject var animator: CodingCharacterAnimator
    var body: some View { Image(nsImage: animator.image).renderingMode(.original).accessibilityLabel("코딩하는 dony") }
}
