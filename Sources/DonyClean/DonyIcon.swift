import SwiftUI
import AppKit

/// The same Phosphor fill family used by the Dony sidebar.
struct DonyIcon: View {
    let symbol: String
    let size: CGFloat
    init(_ symbol: String, size: CGFloat = 20) { self.symbol = symbol; self.size = size }
    private static let names: [String: String] = [
        "house": "house-fill", "square.grid.2x2": "squares-four-fill",
        "sparkles": "broom-fill", "folder": "folder-simple-fill", "folder.fill": "folder-simple-fill",
        "waveform.path.ecg": "gauge-fill", "square.stack.3d.up": "squares-four-fill",
        "clock.arrow.circlepath": "clock-counter-clockwise-fill", "cpu": "cpu-fill",
        "memorychip": "memory-fill", "externaldrive": "hard-drive-fill", "doc.fill": "file-fill",
        "doc.text.magnifyingglass": "file-fill", "doc.on.doc": "copy-simple-fill",
        "gearshape": "gear-fill", "gearshape.2": "gear-fill", "laptopcomputer": "laptop-fill",
        "leaf": "memory-fill", "checkmark.circle": "check-circle-fill", "checkmark.circle.fill": "check-circle-fill",
        "exclamationmark.circle.fill": "warning-circle-fill", "info.circle": "info-fill",
        "lock": "lock-fill", "lock.fill": "lock-fill", "power": "power-fill",
        "magnifyingglass": "magnifying-glass", "arrow.up.forward.square": "arrow-square-out",
        "arrow.left.arrow.right": "arrows-left-right", "arrow.clockwise": "arrow-clockwise",
        "ellipsis": "dots-three", "chevron.right": "caret-right-bold", "xmark": "x-bold",
        "checkmark": "check-bold", "trash": "broom-fill", "app.badge.checkmark": "squares-four-fill"
    ]
    private static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in Set(names.values) {
            if let url = Bundle.main.url(forResource: name, withExtension: "pdf", subdirectory: "Icons"), let image = NSImage(contentsOf: url) {
                image.isTemplate = true; result[name] = image
            }
        }
        return result
    }()
    var body: some View {
        if let image = Self.images[Self.names[symbol] ?? symbol] {
            Image(nsImage: image).resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
struct DonyLabel: View {
    let title: String
    let icon: String
    init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    var body: some View { HStack(spacing: 7) { DonyIcon(icon, size: 18); Text(title) } }
}
