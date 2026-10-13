import SwiftUI
import DonyCore

struct ToolSelectionView: View {
    @Binding var selection: Set<AITool>
    var statuses: [AITool: String] = [:]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
            ForEach(AITool.allCases) { tool in
                Button {
                    if selection.contains(tool) { selection.remove(tool) } else { selection.insert(tool) }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5).fill(selection.contains(tool) ? Theme.primary : Color.white).frame(width: 18, height: 18)
                            if selection.contains(tool) { DonyIcon("checkmark", size: 10).foregroundStyle(.white) }
                            else { RoundedRectangle(cornerRadius: 5).stroke(Theme.line, lineWidth: 1.5).frame(width: 18, height: 18) }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.title).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.body).lineLimit(1)
                            if let status = statuses[tool] { Text(status).font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }.padding(10).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading).background(selection.contains(tool) ? Theme.blueWash : Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityValue(selection.contains(tool) ? "선택됨" : "선택 안 됨")
            }
        }
    }
}
