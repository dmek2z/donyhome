import AppKit
import Testing
import DonyCore
@testable import DonyClean

@Suite(.serialized) @MainActor struct ClipboardPopupTests {
    func controller(popup: ClipboardPanel? = nil) throws -> (ClipboardController, NSPasteboard, URL, String) {
        _ = NSApplication.shared
        let name = "dony-popup-test-" + UUID().uuidString
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appendingPathComponent("history.json")
        let first = ClipboardItem(representations: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("first fixture".utf8))]])
        var second = ClipboardItem(representations: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("second fixture".utf8)), ClipboardRepresentation(type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<b>second fixture</b>".utf8))]])
        second.lastCopiedAt = first.lastCopiedAt.addingTimeInterval(-1)
        try ClipboardStore(url: store).save([first, second])
        let defaults = UserDefaults(suiteName: name)!
        return (ClipboardController(pasteboard: board, storeURL: store, defaults: defaults, popup: popup), board, directory, name)
    }
    func cleanup(_ fixture: (ClipboardController, NSPasteboard, URL, String)) {
        fixture.0.stop(); fixture.1.releaseGlobally()
        try? FileManager.default.removeItem(at: fixture.2)
        UserDefaults.standard.removePersistentDomain(forName: fixture.3)
    }
    @Test func numberedShortcutWritesTheActualPrivatePasteboardAndPromotesTheItem() throws {
        let f = try controller(); defer { cleanup(f) }
        let second = f.0.visibleItems[1]
        #expect(f.0.copyShortcut("2"))
        #expect(f.1.string(forType: .string) == "second fixture")
        #expect(f.1.string(forType: .html) == "<b>second fixture</b>")
        #expect(f.0.currentCopiedItemID == second.id)
        #expect(f.0.visibleItems.first?.id == second.id)
    }
    @Test func externalChangeInvalidatesTheCurrentCopyMarkerEvenWhenCaptureIsPaused() throws {
        let f = try controller(); defer { cleanup(f) }
        #expect(f.0.copyShortcut("2"))
        f.0.preferences.paused = true
        f.1.clearContents(); f.1.setString("outside fixture", forType: .string)
        f.0.poll()
        #expect(f.0.currentCopiedItemID == nil)
        #expect(f.1.string(forType: .string) == "outside fixture")
    }
    @Test func invalidNumberDoesNotWriteOrChangeTheClipboard() throws {
        let f = try controller(); defer { cleanup(f) }
        f.1.setString("keep fixture", forType: .string)
        #expect(!f.0.copyShortcut("9"))
        #expect(!f.0.copyShortcut("0"))
        #expect(!f.0.copyShortcut("text"))
        #expect(f.1.string(forType: .string) == "keep fixture")
    }
    @Test func popupAndItsSettingsRemainInteractiveDuringAnotherAppModal() throws {
        let f = try controller(); defer { cleanup(f) }
        let popup = ClipboardPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        let settings = f.0.makeQuickSettingsPanel()
        defer { popup.close(); settings.close() }
        #expect(popup.worksWhenModal)
        #expect(popup.canBecomeKey)
        #expect(settings.worksWhenModal)
        #expect(settings.canBecomeKey)
        #expect(settings.contentView != nil)
    }
    @Test func editingACopiedItemCannotClaimTheEditedBytesAreAlreadyCopied() throws {
        let f = try controller(); defer { cleanup(f) }
        #expect(f.0.copyShortcut("2"))
        let item = f.0.visibleItems[0]
        f.0.edit(item, text: "edited fixture")
        #expect(!f.0.isCurrentCopy(f.0.visibleItems[0]))
        #expect(f.1.string(forType: .string) == "second fixture")
    }
    @Test func closingSettingsCancelsShortcutRecordingSynchronously() throws {
        let f = try controller(); defer { cleanup(f) }
        let window = f.0.makeQuickSettingsPanel()
        var cancelled = false
        f.0.registerShortcutRecorder(id: UUID(), cancel: { cancelled = true })
        window.close()
        #expect(cancelled)
    }

    @Test func quickNumbersFollowLatestCopyInsteadOfPermanentSlotsOrManagementSort() throws {
        let f = try controller(); defer { cleanup(f) }
        let first = f.0.quickItems[0]; let second = f.0.quickItems[1]
        f.0.preferences.sort = .firstCopiedAt
        #expect(f.0.copyShortcut("2"))
        #expect(f.0.quickItems[0].id == second.id)
        #expect(f.0.copyShortcut("1"))
        #expect(f.1.string(forType: .string) == "second fixture")
        #expect(f.0.copyShortcut("2"))
        #expect(f.1.string(forType: .string) == "first fixture")
        #expect(f.0.quickItems[0].id == first.id)
    }
    @Test func successfulCopyHidesTheActualPopupWindow() throws {
        _ = NSApplication.shared
        let popup = ClipboardPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        let f = try controller(popup: popup); defer { popup.close(); cleanup(f) }
        popup.orderFront(nil)
        #expect(popup.isVisible)
        #expect(f.0.copyShortcut("2"))
        #expect(!popup.isVisible)
    }
    @Test func copyingOutsideAlsoClosesThePopupEvenWithHistoryPaused() throws {
        _ = NSApplication.shared
        let popup = ClipboardPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        let f = try controller(popup: popup); defer { popup.close(); cleanup(f) }
        f.0.preferences.paused = true
        popup.orderFront(nil)
        #expect(popup.isVisible)
        f.1.clearContents()
        #expect(f.1.setString("external fixture", forType: .string))
        f.0.poll()
        #expect(!popup.isVisible)
        #expect(f.1.string(forType: .string) == "external fixture")
    }

}
