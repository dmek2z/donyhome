import SwiftUI

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
