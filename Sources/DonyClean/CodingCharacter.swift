import AppKit

@MainActor enum CodingCharacter {
    // MenuBarExtra extracts native images; the image itself must have menu-bar dimensions.
    static let images: [NSImage] = (0..<4).map { index in
        let frame = index % 2
        let rows = ["    hhhhh         ", "   hhhhhhh        ", "   hsssssh        ", "   sskssks        ", "    sssss         ", "    bbbbb  kkkkkk ", "   bbbbbbb kmggmk ", frame == 0 ? "   bbssbbb kmmgmk " : "   bbbssbb kmggmk ", frame == 0 ? "     s ss  kkkkkk " : "    ss s   kkkkkk ", "  mmmmmmmmmmmkkmmm", "  kkkkkkkkkkkkkkkk", "    kk  kk        "]
        let colors: [Character: NSColor] = ["h": NSColor(red: 0.25, green: 0.18, blue: 0.38, alpha: 1), "s": NSColor(red: 1, green: 0.76, blue: 0.55, alpha: 1), "b": NSColor(red: 0.25, green: 0.53, blue: 1, alpha: 1), "k": NSColor(red: 0.12, green: 0.18, blue: 0.29, alpha: 1), "m": NSColor(red: 0.62, green: 0.76, blue: 0.91, alpha: 1), "g": NSColor(red: 0.32, green: 0.96, blue: 0.69, alpha: 1)]
        let image = NSImage(size: NSSize(width: 27, height: 18), flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .none
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() {
                    if let color = colors[char] { color.setFill(); NSRect(x: CGFloat(x) * 1.5, y: CGFloat(11 - y) * 1.5, width: 1.5, height: 1.5).fill() }
                }
            }
            if index >= 2 { NSColor.cyan.setFill(); NSRect(x: frame == 0 ? 3 : 24, y: 12, width: 1.5, height: 3).fill() }
            return true
        }
        image.isTemplate = false
        return image
    }
}
