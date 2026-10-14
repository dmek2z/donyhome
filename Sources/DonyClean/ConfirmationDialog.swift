import SwiftUI
import AppKit

@MainActor final class ConfirmationPanel: NSPanel {
    var returnResponse: NSApplication.ModalResponse = .cancel
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.keyCode == 53 { cancelOperation(nil); return }
            if event.keyCode == 36 || event.keyCode == 76 { NSApp.stopModal(withCode: returnResponse); orderOut(nil); return }
        }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) { NSApp.stopModal(withCode: .cancel); orderOut(nil) }
}
@MainActor enum ConfirmationDialog {
    static func show(title: String, message: String, action: String, destructive: Bool, paths: [String]) -> Bool {
        let panel = ConfirmationPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: paths.isEmpty ? 220 : 480), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.returnResponse = destructive ? .cancel : .OK
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named: .aqua)
        panel.contentView = NSHostingView(rootView: ConfirmationContent(title: title, message: message, action: action, destructive: destructive, paths: paths) { accepted in
            NSApp.stopModal(withCode: accepted ? .OK : .cancel); panel.orderOut(nil)
        })
        panel.center(); panel.makeKeyAndOrderFront(nil)
        let result = NSApp.runModal(for: panel)
        panel.contentView = nil
        panel.close()
        return result == .OK
    }
}
private struct ConfirmationContent: View {
    let title: String
    let message: String
    let action: String
    let destructive: Bool
    let paths: [String]
    let completion: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(Theme.font(22, weight: .bold)).lineLimit(2)
            Text(message).font(Theme.font(13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if !paths.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                            Text(path).font(Theme.font(12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            Divider()
                        }
                    }
                }.frame(maxHeight: .infinity).background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Spacer()
                if destructive { Button("취소") { completion(false) }.buttonStyle(QuietButton()).keyboardShortcut(.defaultAction) }
                else { Button("취소") { completion(false) }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction) }
                if destructive { Button(action) { completion(true) }.buttonStyle(PrimaryButton()) }
                else { Button(action) { completion(true) }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction) }
            }
        }.padding(24).frame(width: 560, height: paths.isEmpty ? 220 : 480).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
    }
}
