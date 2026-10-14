import SwiftUI
import AppKit

@MainActor final class ConfirmationPanel: NSPanel, NSWindowDelegate {
    var acceptOnReturn = false
    var completion: ((Bool) -> Void)?
    override var canBecomeKey: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.keyCode == 53 { cancelOperation(nil); return }
            if event.keyCode == 36 || event.keyCode == 76 { completion?(acceptOnReturn); return }
        }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) { completion?(false) }
    override func close() { completion?(false); super.close() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { completion?(false); return false }
}

/// Suspend the caller, never the AppKit/SwiftUI event loop. One review at a time.
@MainActor enum ConfirmationDialog {
    private struct Session {
        let id: UUID
        let panel: ConfirmationPanel
        let continuation: CheckedContinuation<Bool, Never>
    }
    private static var session: Session?
    static var presentedPanel: ConfirmationPanel? { session?.panel }

    static func show(title: String, message: String, action: String, destructive: Bool, paths: [String], parent: NSWindow? = nil) async -> Bool {
        guard !Task.isCancelled else { return false }
        if let current = session { current.panel.makeKeyAndOrderFront(nil); return false }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                let panel = ConfirmationPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: paths.isEmpty ? 220 : 480), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                panel.acceptOnReturn = !destructive
                panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
                panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named: .aqua)
                panel.delegate = panel
                panel.completion = { accepted in finish(id: id, accepted: accepted) }
                panel.contentView = NSHostingView(rootView: ConfirmationContent(title: title, message: message, action: action, destructive: destructive, paths: paths) { accepted in
                    finish(id: id, accepted: accepted)
                })
                session = Session(id: id, panel: panel, continuation: continuation)
                if let parent = parent ?? NSApp.keyWindow, parent.isVisible, parent.canBecomeMain, parent.attachedSheet == nil {
                    parent.beginSheet(panel) { _ in finish(id: id, accepted: false) }
                } else {
                    panel.level = .modalPanel; panel.center(); panel.makeKeyAndOrderFront(nil)
                }
            }
        } onCancel: {
            Task { @MainActor in finish(id: id, accepted: false) }
        }
    }

    private static func finish(id: UUID, accepted: Bool) {
        guard let current = session, current.id == id else { return }
        session = nil
        current.panel.completion = nil; current.panel.delegate = nil
        if let parent = current.panel.sheetParent { parent.endSheet(current.panel) }
        current.panel.orderOut(nil)
        // Let the originating SwiftUI Button finish before releasing its hosting view.
        DispatchQueue.main.async { current.panel.contentView = nil; current.panel.close() }
        current.continuation.resume(returning: accepted)
    }
}

/// Native file pickers must also return from the originating SwiftUI action.
@MainActor enum OpenPanelPresenter {
    private static var panel: NSOpenPanel?
    static func show(_ requested: NSOpenPanel) async -> Bool {
        guard panel == nil, !Task.isCancelled else { return false }
        panel = requested
        defer { panel = nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                requested.begin { response in continuation.resume(returning: response == .OK) }
            }
        } onCancel: {
            Task { @MainActor in if panel === requested { requested.cancel(nil) } }
        }
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
