import SwiftUI

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
