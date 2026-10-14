#if DEBUG
import AppKit
import Combine
import DonyCore

/// Disposable native UI reproduction: enabled only by a test bundle marker.
/// It never opens the general pasteboard or the user's clipboard store.
@MainActor enum ClipboardUIFixture {
    static func runIfRequested() -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "DonyClipboardFixture") as? Bool == true,
              let path = Bundle.main.object(forInfoDictionaryKey: "DonyFixtureDirectory") as? String else { return false }
        let directory = URL(fileURLWithPath: path)
        let board = NSPasteboard(name: .init("donyhome-ui-fixture"))
        let defaultsName = "donyhome-ui-fixture-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: defaultsName)!
        var preferences = ClipboardPreferences(); preferences.hotkeyEnabled = false
        defaults.set(try! JSONEncoder().encode(preferences), forKey: "clipboard.preferences")
        let store = ClipboardStore(url: directory.appendingPathComponent("history.json"))
        var pinned = ClipboardItem(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("고정한 테스트 기록".utf8))]])
        pinned.pinned = true
        let recent = ClipboardItem(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("지울 테스트 기록".utf8))]])
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! store.save([pinned, recent])
        board.clearContents(); board.setString("현재 테스트 복사", forType: .string)
        let controller = ClipboardController(pasteboard: board, storeURL: store.url, defaults: defaults)
        func saveState() {
            let state: [String: Any] = ["memoryCount": controller.items.count, "storedCount": (try? store.load().count) ?? -1, "pasteboardItemCount": board.pasteboardItems?.count ?? 0]
            try! JSONSerialization.data(withJSONObject: state).write(to: directory.appendingPathComponent("state.json"))
        }
        let subscription = controller.$items.sink { _ in DispatchQueue.main.async { saveState() } }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "테스트 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem); app.mainMenu = menu
        DispatchQueue.main.async { controller.showPopup(); saveState() }
        app.run()
        withExtendedLifetime(subscription) { controller.stop(); saveState() }
        board.releaseGlobally()
        defaults.removePersistentDomain(forName: defaultsName)
        return true
    }
}
#endif
