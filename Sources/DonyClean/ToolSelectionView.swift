import AppKit
import SwiftUI
import DonyCore

struct ToolSelectionView: View {
    @Binding var selection: Set<AITool>
    var statuses: [AITool: String] = [:]
    var tools: [AITool] = AITool.allCases
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
            ForEach(tools) { tool in
                Button {
                    if selection.contains(tool) { selection.remove(tool) } else { selection.insert(tool) }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5).fill(selection.contains(tool) ? Theme.primary : Color.white).frame(width: 18, height: 18)
                            if selection.contains(tool) { DonyIcon("checkmark", size: 10).foregroundStyle(.white) }
                            else { RoundedRectangle(cornerRadius: 5).stroke(Theme.line, lineWidth: 1.5).frame(width: 18, height: 18) }
                        }
                        ToolIcon(tool: tool, size: 22)
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

/// 설치된 앱의 실제 아이콘을 보여준다. CLI만 있는 도구는 이니셜 배지로 대신한다.
struct ToolIcon: View {
    let tool: AITool
    var size: CGFloat = 28
    private static var cache: [AITool: NSImage?] = [:]
    private static func appIcon(_ tool: AITool) -> NSImage? {
        if let cached = cache[tool] { return cached }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let names = ([tool.title] + tool.executableNames).filter { !$0.isEmpty }
        let roots = ["/Applications/", home.appendingPathComponent("Applications").path + "/", "/System/Applications/", "/System/Applications/Utilities/"]
        let path = names.lazy.flatMap { name in roots.map { $0 + name + ".app" } }.first { FileManager.default.fileExists(atPath: $0) }
        let icon = path.map { NSWorkspace.shared.icon(forFile: $0) }
        cache[tool] = icon
        return icon
    }
    var body: some View {
        if let icon = Self.appIcon(tool) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Text(String(tool.title.prefix(1)).uppercased()).font(Theme.font(size * 0.45, weight: .bold)).foregroundStyle(Theme.secondary)
                .frame(width: size, height: size).background(Theme.controlFill).clipShape(RoundedRectangle(cornerRadius: size * 0.25))
        }
    }
}
