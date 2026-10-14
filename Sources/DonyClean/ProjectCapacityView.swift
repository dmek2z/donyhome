import SwiftUI
import DonyCore

/// The area of each tile represents its measured bytes. Unknown/zero entries
/// stay in the project list instead of receiving an invented chart area.
struct ProjectCapacityView: View {
    let entries: [ProjectInventoryEntry]
    let selectedPath: String?
    let select: (String) -> Void
    @State private var hoveredPath: String?
    private var measured: [ProjectInventoryEntry] { entries.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes } }
    private var visible: [ProjectInventoryEntry] { Array(measured.prefix(8)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("프로젝트 용량").font(Theme.font(17, weight: .semibold))
                Spacer()
                Text(measured.isEmpty ? "아직 확인되지 않았어요" : DisplayFormat.bytes(measured.reduce(0) { $0 + $1.bytes })).font(Theme.font(17, weight: .semibold)).monospacedDigit()
            }
            if visible.isEmpty {
                VStack(spacing: 10) {
                    DonyIcon("folder", size: 28).foregroundStyle(Theme.primary)
                    Text("검사하면 용량 분포를 볼 수 있어요").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity).frame(height: 190).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                GeometryReader { geometry in
                    let frames = tileFrames(visible, within: CGRect(origin: .zero, size: geometry.size))
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(visible.enumerated()), id: \.element.path) { index, entry in
                            let frame = frames[index]
                            capacityTile(entry, index: index, frame: frame)

                        }
                    }
                }.frame(height: 210)
            }
            Text(chartFootnote).font(Theme.font(11)).foregroundStyle(Theme.secondary)
        }
    }
    private func capacityTile(_ entry: ProjectInventoryEntry, index: Int, frame: CGRect) -> some View {
        let selected = selectedPath == entry.path
        let name = URL(fileURLWithPath: entry.path).lastPathComponent
        let size = DisplayFormat.bytes(entry.bytes)
        let label = name + " · " + size + (entry.issues.isEmpty ? "" : " · 일부 결과")
        let fill: Color = selected ? Theme.primary : Theme.primary.opacity(0.12 + Double(index % 4) * 0.035)
        let ink: Color = selected ? Color.white : Theme.ink
        let border: Color = hoveredPath == entry.path ? Theme.primary : Color.clear
        return Button { select(entry.path) } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(fill)
                if frame.width > 76 && frame.height > 48 {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name).font(Theme.font(12, weight: .semibold)).lineLimit(2)
                        Text(size).font(Theme.font(11)).monospacedDigit().lineLimit(1)
                    }.padding(10).foregroundStyle(ink)
                }
            }.frame(width: max(0, frame.width - 4), height: max(0, frame.height - 4))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 2) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).position(x: frame.midX - 2, y: frame.midY - 2)
            .help(label).accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .onHover { inside in hoveredPath = inside ? entry.path : nil }
    }
    private var chartFootnote: String {
        let partial = entries.contains { !$0.issues.isEmpty }
        return (measured.count > 8 ? "상위 8개 분포 · " : "확인된 용량 기준 · ") + (partial ? "일부 결과 포함 · 미확인 항목 제외" : "면적은 용량에 비례해요")
    }
    private func tileFrames(_ items: [ProjectInventoryEntry], within rect: CGRect) -> [CGRect] {
        guard items.count > 1 else { return items.isEmpty ? [] : [rect] }
        let total = items.reduce(Double(0)) { $0 + Double($1.bytes) }
        var subtotal = Double(0), split = 1
        var closest = Double.greatestFiniteMagnitude
        for index in 1..<items.count {
            subtotal += Double(items[index - 1].bytes)
            let distance = abs(total / 2 - subtotal)
            if distance < closest { closest = distance; split = index }
        }
        let left = Array(items.prefix(split)), right = Array(items.dropFirst(split))
        let ratio = left.reduce(Double(0)) { $0 + Double($1.bytes) } / max(1, total)
        let first: CGRect, second: CGRect
        if rect.width >= rect.height {
            let width = rect.width * ratio
            first = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            second = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            let height = rect.height * ratio
            first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
            second = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }
        return tileFrames(left, within: first) + tileFrames(right, within: second)
    }
}
