import AppKit
import SwiftUI
import Testing
import DonyCore
@testable import DonyClean

@Suite(.serialized) @MainActor struct ConfirmationDialogTests {
    static func click(_ window: NSWindow, at point: NSPoint) {
        window.contentView?.layoutSubtreeIfNeeded()
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
    }
    func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition(), "UI action did not complete within 4 seconds")
        throw FixtureError.timeout
    }
    enum FixtureError: Error { case timeout }
    func review(destructive: Bool = true, paths: [String] = ["/fixture/temporary-file"]) -> Task<Bool, Never> {
        _ = NSApplication.shared
        return Task { await ConfirmationDialog.show(title: "fixture", message: "temporary files only", action: "이동", destructive: destructive, paths: paths) }
    }
    func key(_ panel: NSWindow, code: UInt16) {
        panel.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
    }
    @Test(arguments: [false, true])
    func hostedAcceptButtonRespondsToMouseIncludingItsPaddedBackground(edge: Bool) async throws {
        let task = review(); defer { task.cancel() }
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        let panel = try #require(ConfirmationDialog.presentedPanel)
        #expect(NSApp.modalWindow == nil)
        Self.click(panel, at: NSPoint(x: edge ? 532 : 480, y: 45))
        try await waitFor { ConfirmationDialog.presentedPanel == nil }
        #expect(await task.value)
    }
    @Test func cancelButtonDoesNotAcceptTheOperation() async throws {
        let task = review(); defer { task.cancel() }
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        Self.click(try #require(ConfirmationDialog.presentedPanel), at: NSPoint(x: 432, y: 45))
        try await waitFor { ConfirmationDialog.presentedPanel == nil }
        #expect(!(await task.value))
    }
    @Test(arguments: [(true, UInt16(36), false), (false, UInt16(36), true), (false, UInt16(53), false)])
    func keyboardDefaultAndEscapeRespectDestructiveSafety(input: (Bool, UInt16, Bool)) async throws {
        let task = review(destructive: input.0); defer { task.cancel() }
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        key(try #require(ConfirmationDialog.presentedPanel), code: input.1)
        #expect(await task.value == input.2)
    }
    @Test func windowCloseResolvesCancellation() async throws {
        let task = review(); defer { task.cancel() }
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        ConfirmationDialog.presentedPanel?.close()
        #expect(!(await task.value))
        #expect(ConfirmationDialog.presentedPanel == nil)
    }
    @Test func cancelledTaskReleasesTheReviewAndAllowsAnotherReview() async throws {
        let task = review()
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        task.cancel()
        #expect(!(await task.value))
        let next = review(); defer { next.cancel() }
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        ConfirmationDialog.presentedPanel?.cancelOperation(nil)
        #expect(!(await next.value))
    }
    @Test func secondReviewDoesNotExecuteOrDismissTheFirstReview() async throws {
        let first = review(); defer { first.cancel() }
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        let panel = ConfirmationDialog.presentedPanel
        let second = review()
        #expect(!(await second.value))
        #expect(ConfirmationDialog.presentedPanel === panel)
        panel?.cancelOperation(nil)
        #expect(!(await first.value))
    }
    @Test func originalSwiftUIButtonReturnsBeforeItsSheetAndMouseAcceptExecutesOnce() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var completions = 0
        var task: Task<Void, Never>?
        window.contentView = NSHostingView(rootView: Button("검토") {
            task = Task {
                if await ConfirmationDialog.show(title: "fixture", message: "temporary files", action: "이동", destructive: true, paths: ["/fixture/file"], parent: window) { completions += 1 }
            }
        }.buttonStyle(PrimaryButton()).frame(width: 560, height: 140))
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(100))
        defer { task?.cancel(); window.close() }
        Self.click(window, at: NSPoint(x: 280, y: 70))
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        let panel = try #require(ConfirmationDialog.presentedPanel)
        #expect(panel.sheetParent === window)
        #expect(NSApp.modalWindow == nil)
        Self.click(panel, at: NSPoint(x: 480, y: 45))
        try await waitFor { completions == 1 }
        #expect(window.attachedSheet == nil)
    }

    @Test func modelTrashButtonCancelThenAcceptMoves78TemporaryFilesAndPersistsRealResults() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dony-ui-cleanup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = HistoryStore(directory: directory.appendingPathComponent("history"))
        let model = AppModel(store: store, automaticallySample: false)
        model.automaticStorageCheck = false; model.storageAlertsEnabled = false; model.notifyEnabled = false
        model.automaticCleanupEnabled = false; model.onboardingShown = false; model.resumedScanChecked = true
        let files = try (0..<78).map { index -> FileCandidate in
            let url = directory.appendingPathComponent("fixture-\(index).txt")
            try Data("temporary file \(index)".utf8).write(to: url)
            return try FileCandidate.capture(url: url, root: directory, kind: .large)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Button("휴지통으로 이동") { model.moveToTrash(files) }.buttonStyle(PrimaryButton()).frame(width: 560, height: 140))
        window.makeKeyAndOrderFront(nil)
        defer {
            ConfirmationDialog.presentedPanel?.cancelOperation(nil)
            window.close()
            // Restore only files created by this test; never enumerate or empty Trash.
            for record in model.history where record.success {
                if let trash = record.trashPath, FileManager.default.fileExists(atPath: trash) {
                    try? FileManager.default.moveItem(atPath: trash, toPath: record.sourcePath)
                }
            }
            try? FileManager.default.removeItem(at: directory)
        }
        Self.click(window, at: NSPoint(x: 280, y: 70))
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        #expect(model.busy)
        Self.click(try #require(ConfirmationDialog.presentedPanel), at: NSPoint(x: 360, y: 45))
        try await waitFor { !model.busy }
        #expect(model.history.isEmpty)
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.id) })
        Self.click(window, at: NSPoint(x: 280, y: 70))
        try await waitFor { ConfirmationDialog.presentedPanel != nil }
        Self.click(try #require(ConfirmationDialog.presentedPanel), at: NSPoint(x: 480, y: 45))
        // Actual 78-file movement can take longer than a simple UI transition.
        for _ in 0..<500 { if !model.busy { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.busy)
        #expect(model.history.count == 78)
        #expect(model.history.allSatisfy { $0.success })
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.id) })
        #expect(try store.load().count == 78)
        #expect(model.lastCleanupOutcome?.successful == 78)
    }
}
