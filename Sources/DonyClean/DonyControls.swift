import SwiftUI
import DonyCore

struct DonyIconMenu<Content: View>: View {
    let title: String
    var size: CGFloat = 32
    @ViewBuilder let content: () -> Content
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Menu(content: content) { Text(" ") }
            .menuStyle(.button).buttonStyle(MenuHitAreaStyle(width: size, height: size)).menuIndicator(.hidden)
            .frame(width: size, height: size)
            .overlay {
                DonyIcon("ellipsis", size: 16).frame(width: size, height: size)
                    .foregroundStyle(enabled ? Theme.body : Theme.secondary.opacity(0.55))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }.contentShape(Rectangle()).fixedSize().accessibilityLabel(title).help(title)
    }
}

struct DonySearchField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 6) {
            DonyIcon("magnifyingglass", size: 14).foregroundStyle(Theme.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain)
        }.font(Theme.font(12)).padding(.horizontal, 12).frame(height: 42).background(.white).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// Settings and utility rows share one action column, regardless of label length.
struct SettingsActionRow: View {
    let title: String
    let actionTitle: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            Text(title).font(Theme.font(16, weight: .semibold))
            Spacer(minLength: 12)
            Button(action: action) { Text(actionTitle).frame(width: Theme.actionWidth - 24) }.buttonStyle(QuietButton()).disabled(!enabled)
        }
    }
}

struct SelectionControl: View {
    @Binding var selection: Set<String>
    let ids: [String]
    var recommended: [String]? = nil
    var body: some View {
        HStack(spacing: 12) {
            if let recommended {
                DonyTextAction(title: "추천 선택") { selection = Set(recommended) }.disabled(recommended.isEmpty)
            }
            DonyTextAction(title: selection.isEmpty ? "전체 선택" : "선택 해제") {
                if selection.isEmpty { selection = Set(ids) } else { selection.removeAll() }
            }.disabled(ids.isEmpty && selection.isEmpty)
        }.fixedSize()
    }
}

/// Secondary actions stay visible and share a 42pt hit area without menu chrome.
struct DonyTextAction: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.font(13, weight: .medium))
                .foregroundStyle(enabled ? Theme.primary : Theme.secondary.opacity(0.55))
                .padding(.horizontal, 4).frame(height: Theme.controlHeight).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct DonyFilterChips: View {
    let options: [String]
    @Binding var selection: String
    /// 옵션 이름에 해당하는 도구가 있으면 칩 앞에 도구 로고를 보여준다.
    var icons: [String: AITool] = [:]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        HStack(spacing: 8) {
                            if let tool = icons[option] { ToolIcon(tool: tool, size: 20) }
                            Text(option).font(Theme.font(13, weight: .medium)).lineLimit(1)
                        }
                            .foregroundStyle(selection == option ? Theme.primary : Theme.secondary)
                            .padding(.leading, icons[option] == nil ? 14 : 10).padding(.trailing, 14).frame(height: Theme.controlHeight)
                            .background(selection == option ? Theme.blueWash : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
        }.frame(height: Theme.controlHeight)
    }
}

struct DonySwitch: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 16) {
                configuration.label.font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.body).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Capsule().fill(configuration.isOn ? Theme.primary : Color(hex: 0xd1d6db))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) { Circle().fill(.white).padding(3).frame(width: 24, height: 24) }
                    .frame(width: 42, height: 24)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(configuration.isOn ? "켜짐" : "꺼짐").opacity(enabled ? 1 : 0.5)
    }
}

struct DonyChoices: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        GeometryReader { geometry in
            let width = max(0, (geometry.size.width - 8 - CGFloat(max(0, options.count - 1)) * 4) / CGFloat(max(1, options.count)))
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { value in
                    Button { selection = value } label: {
                        Text(value).font(Theme.font(13, weight: selection == value ? .semibold : .medium)).foregroundStyle(selection == value ? Theme.primary : Theme.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8).frame(width: width, height: 38)
                            .background(selection == value ? Color.white : Color.clear).clipShape(RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == value ? .isSelected : [])
                }
            }.padding(4)
        }.frame(height: 46).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DonyCheckbox: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(configuration.isOn ? Theme.primary : .white)
                RoundedRectangle(cornerRadius: 6).stroke(configuration.isOn ? Theme.primary : Color(hex: 0xd1d6db), lineWidth: 1.4)
                if configuration.isOn { DonyIcon("checkmark", size: 12).foregroundStyle(.white) }
            }.frame(width: 20, height: 20).frame(width: 32, height: 32).contentShape(Rectangle()).opacity(enabled ? 1 : 0.4)
        }.buttonStyle(.plain).accessibilityValue(configuration.isOn ? "선택됨" : "선택 안 됨")
    }
}

struct DonyTabs: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 24) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    VStack(spacing: 11) {
                        Text(option).font(Theme.font(14, weight: selection == option ? .semibold : .medium)).foregroundStyle(selection == option ? Theme.body : Theme.secondary)
                        Rectangle().fill(selection == option ? Theme.body : .clear).frame(height: 2)
                    }.fixedSize(horizontal: true, vertical: false)
                }.buttonStyle(.plain).accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }.padding(.top, 10).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).offset(y: 1) }
    }
}

private struct MenuHitAreaStyle: ButtonStyle {
    let width: CGFloat
    let height: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: width, height: height).contentShape(Rectangle())
    }
}


/// Bounded detail rows with access to every candidate, using shared buttons.
struct ListPagination: View {
    let total: Int
    @Binding var page: Int
    private var lastPage: Int { max(0, (total - 1) / 100) }
    var body: some View {
        if total > 100 {
            HStack {
                Text("\(page * 100 + 1)–\(min(total, (page + 1) * 100)) / \(total)개").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                Spacer()
                DonyTextAction(title: "이전") { page = max(0, page - 1) }.disabled(page == 0)
                DonyTextAction(title: "다음") { page = min(lastPage, page + 1) }.disabled(page >= lastPage)
            }.onChange(of: total) { _, _ in page = min(page, lastPage) }
        }
    }
}
