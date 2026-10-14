#if DEBUG
import AppKit
import SwiftUI
import Combine
import DonyCore

/// Runs the production root/views against an isolated bundle, history and pasteboard.
/// Destructive verification is restricted to 78 files created in this fixture directory.
@MainActor enum ActionUIFixture {
    static func runIfRequested() -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "DonyActionFixture") as? Bool == true,
              let path = Bundle.main.object(forInfoDictionaryKey: "DonyFixtureDirectory") as? String else { return false }
        let directory = URL(fileURLWithPath: path)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try! (0..<78).map { index -> FileCandidate in
            let url = directory.appendingPathComponent("fixture-\(index).txt")
            try Data("Temporary verification file \(index)".utf8).write(to: url)
            return try FileCandidate.capture(url: url, root: directory, kind: .large)
        }
        let model = AppModel(store: HistoryStore(directory: directory.appendingPathComponent("actions")), automaticallySample: false)
        model.automaticStorageCheck = false; model.storageAlertsEnabled = false; model.notifyEnabled = false
        model.automaticCleanupEnabled = false; model.onboardingShown = false; model.resumedScanChecked = true
        model.permissionSetupReviewed = true; model.folder = directory
        model.largeFiles.items = files; model.filesDate = Date()
        model.section = .files
        let board = NSPasteboard(name: .init("donyhome-action-fixture-" + UUID().uuidString))
        var preferences = ClipboardPreferences(); preferences.hotkeyEnabled = false
        UserDefaults.standard.set(try! JSONEncoder().encode(preferences), forKey: "clipboard.preferences")
        let store = ClipboardStore(url: directory.appendingPathComponent("clipboard.json"))
        let recent = ClipboardItem(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("임시 복사 기록".utf8))]])
        try! store.save([recent]); board.setString("임시 복사 내용", forType: .string)
        let clipboard = ClipboardController(pasteboard: board, storeURL: store.url)
        let lifecycle = DonyAppDelegate()
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let menu = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "테스트 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem); app.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1130, height: 790), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "도니홈 버튼 검증 · 임시 데이터"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView(lifecycle: lifecycle).environmentObject(model).environmentObject(clipboard).font(Theme.font(14)).preferredColorScheme(.light))
        func saveState() {
            let state: [String: Any] = ["sourceFiles": files.filter { FileManager.default.fileExists(atPath: $0.id) }.count, "successfulMoves": model.history.filter(\.success).count, "historyRecords": model.history.count, "busy": model.busy, "clipboardRecords": clipboard.items.count]
            try! JSONSerialization.data(withJSONObject: state).write(to: directory.appendingPathComponent("state.json"))
            // Return only fixture-owned trash destinations to their original paths.
            if model.history.filter(\.success).count == 78, !model.busy {
                for record in model.history where record.success {
                    if let trash = record.trashPath, FileManager.default.fileExists(atPath: trash), !FileManager.default.fileExists(atPath: record.sourcePath) {
                        try! FileManager.default.moveItem(atPath: trash, toPath: record.sourcePath)
                    }
                }
            }
        }
        let subscription = model.objectWillChange.sink { _ in DispatchQueue.main.async { saveState() } }
        let clipboardSubscription = clipboard.objectWillChange.sink { _ in DispatchQueue.main.async { saveState() } }
        window.center(); window.makeKeyAndOrderFront(nil); saveState()
        app.run()
        withExtendedLifetime([subscription, clipboardSubscription]) { clipboard.stop(); saveState() }
        board.releaseGlobally()
        return true
    }
}
#endif
