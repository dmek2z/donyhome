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

    @Test(arguments: [RunLoop.Mode.eventTracking, RunLoop.Mode.modalPanel])
    func externalCopyIsCapturedWhileTheRunLoopIsTrackingOrModal(mode: RunLoop.Mode) throws {
        let popup = ClipboardPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        let f = try controller(popup: popup); defer { popup.close(); cleanup(f) }
        f.0.preferences.hotkeyEnabled = false
        f.0.start()
        popup.orderFront(nil)
        f.1.clearContents(); #expect(f.1.setString("copy during nested run loop", forType: .string))
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline, f.0.quickItems.first?.text != "copy during nested run loop" {
            _ = RunLoop.main.run(mode: mode, before: min(deadline, Date().addingTimeInterval(0.1)))
        }
        #expect(f.0.quickItems.first?.text == "copy during nested run loop")
        #expect(!popup.isVisible)
    }


    @Test func preparingPopupSynchronizesPendingCopyBeforeRendering() throws {
        let f = try controller(); defer { cleanup(f) }
        f.0.preparePopup()
        f.1.clearContents(); #expect(f.1.setString("copy immediately before opening", forType: .string))
        f.0.preparePopup()
        #expect(f.0.quickItems.first?.text == "copy immediately before opening")
        #expect(f.0.currentCopiedItemID == f.0.quickItems.first?.id)
        #expect(f.0.copyShortcut("1"))
        #expect(f.1.string(forType: .string) == "copy immediately before opening")
    }
    @Test func oneClearAllActionImmediatelyEmptiesHistoryWithoutAnApplicationModal() throws {
        let f = try controller(); defer { cleanup(f) }
        f.0.clearAll()
        #expect(NSApp.modalWindow == nil)
        #expect(f.0.items.isEmpty)
        #expect(try ClipboardStore(url: f.2.appendingPathComponent("history.json")).load().isEmpty)
    }
    @Test func oneClearAllActionAlsoRemovesPinsAndTheCurrentSystemCopy() throws {
        let f = try controller(); defer { cleanup(f) }
        f.0.setPinned(f.0.items[0])
        #expect(f.0.copy(f.0.items[0]))
        f.0.clearAll()
        #expect(f.0.items.isEmpty)
        #expect(try ClipboardStore(url: f.2.appendingPathComponent("history.json")).load().isEmpty)
        #expect(f.1.string(forType: .string) == nil)
        #expect((f.1.pasteboardItems ?? []).isEmpty)
        f.0.poll()
        #expect(f.0.items.isEmpty)
        #expect(!f.0.canClearAll)
    }
    @Test func clearAllCanRemoveASystemCopyEvenWithNoStoredHistory() throws {
        let f = try controller(); defer { cleanup(f) }
        f.0.clear(includePinned: true)
        f.1.clearContents(); f.1.setString("unrecorded fixture", forType: .string)
        #expect(f.0.canClearAll)
        f.0.clearAll()
        #expect(!f.0.canClearAll)
        #expect(f.1.string(forType: .string) == nil)
    }
    @Test func clearingAllIncludesPinsAndPersistsAnEmptyHistoryWithoutErasingTheSystemCopy() throws {
        let f = try controller(); defer { cleanup(f) }
        let pinned = f.0.quickItems[1]; f.0.setPinned(pinned)
        #expect(f.0.copy(pinned))
        f.0.selectStack(f.0.items)
        f.0.query = "old search"
        f.0.clear(includePinned: true)
        #expect(f.0.items.isEmpty)
        #expect(f.0.pasteStack.isEmpty)
        #expect(f.0.currentCopiedItemID == nil)
        #expect(f.0.query.isEmpty)
        #expect(try ClipboardStore(url: f.2.appendingPathComponent("history.json")).load().isEmpty)
        #expect(f.1.string(forType: .string) == "second fixture")
    }
    @Test func clearingOnlyUnpinnedHistoryKeepsThePinnedCurrentCopy() throws {
        let f = try controller(); defer { cleanup(f) }
        let pinned = f.0.quickItems[1]; f.0.setPinned(pinned)
        #expect(f.0.copy(pinned))
        f.0.clear()
        #expect(f.0.items.map(\.id) == [pinned.id])
        #expect(f.0.isCurrentCopy(f.0.items[0]))
    }
    @Test func rebuiltPopupHandlesNumberedAppKitEventsExactlyOnce() async throws {
        let popup = ClipboardPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        let f = try controller(popup: popup); defer { popup.close(); cleanup(f) }
        let secondID = f.0.quickItems[1].id
        for (number, keyCode) in [("2", UInt16(19)), ("1", UInt16(18))] {
            f.0.preparePopup(); popup.orderFront(nil)
            popup.contentView?.layoutSubtreeIfNeeded()
            // Allow the hosting view's actual onAppear to install its monitor.
            try await Task.sleep(for: .milliseconds(100))
            let before = f.0.items.first { $0.id == secondID }!.numberOfCopies
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: popup.windowNumber, context: nil, characters: number, charactersIgnoringModifiers: number, isARepeat: false, keyCode: keyCode)!
            NSApp.sendEvent(event)
            #expect(f.1.string(forType: .string) == "second fixture")
            #expect(f.0.quickItems.first?.id == secondID)
            #expect(f.0.items.first { $0.id == secondID }?.numberOfCopies == before + 1)
            #expect(!popup.isVisible)
        }
    }
}
