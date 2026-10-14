import SwiftUI
import AppKit

@MainActor final class ConfirmationPanel: NSPanel {
    var returnResponse: NSApplication.ModalResponse = .cancel
    var completion: ((Bool) -> Void)?
    private var resolved = false
    func resolve(_ accepted: Bool) {
        guard !resolved else { return }
        resolved = true
        if let callback = completion {
            completion = nil
            orderOut(nil); contentView = nil; close()
            callback(accepted)
        } else {
            NSApp.stopModal(withCode: accepted ? .OK : .cancel); orderOut(nil)
        }
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.keyCode == 53 { cancelOperation(nil); return }
            if event.keyCode == 36 || event.keyCode == 76 { resolve(returnResponse == .OK); return }
        }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) { resolve(false) }
}
@MainActor enum ConfirmationDialog {
    /// Return to SwiftUI's mouse-up/update transaction before awaiting a choice.
    /// A nested runModal here otherwise retains that transaction and queues
    /// subsequent SwiftUI button actions, including the Cancel button itself.
    static func present(title: String, message: String, action: String, destructive: Bool, paths: [String], completion: @escaping (Bool) -> Void) -> ConfirmationPanel {
        let panel = ConfirmationPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: paths.isEmpty ? 220 : 480), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.returnResponse = destructive ? .cancel : .OK
        panel.title = title; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named: .aqua)
        panel.level = .floating; panel.worksWhenModal = true
        panel.completion = completion
        panel.contentView = NSHostingView(rootView: ConfirmationContent(title: title, message: message, action: action, destructive: destructive, paths: paths) { [weak panel] accepted in panel?.resolve(accepted) })
        panel.center(); panel.makeKeyAndOrderFront(nil)
        return panel
    }
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
