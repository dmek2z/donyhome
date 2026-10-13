import Testing
import AppKit
@testable import DonyCore

@Suite struct ClipboardHistoryTests {
    @Test @MainActor func testPrivatePasteboardRoundTripsRichTextImageAndMultipleFiles() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("donyhome-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("fixture only", forType: .string)
        first.setData(Data("{\\rtf1 fixture only}".utf8), forType: .rtf)
        first.setData(Data([0, 1, 2]), forType: .png)
        let second = NSPasteboardItem(); second.setString("file:///tmp/fixture-one.txt", forType: .fileURL)
        let third = NSPasteboardItem(); third.setString("file:///tmp/fixture-two.txt", forType: .fileURL)
        #expect(board.writeObjects([first, second, third]))
        let item = try #require(ClipboardCapture.read(board, application: "example.fixture", preferences: ClipboardPreferences()))
        #expect(item.fileURLs.count == 2)
        #expect(item.text == "fixture only")
        #expect(item.imageData == Data([0, 1, 2]))
        #expect(ClipboardCapture.write(item, to: board))
        #expect(board.pasteboardItems?.count == 3)
        #expect(board.pasteboardItems?.first?.data(forType: .rtf) == Data("{\\rtf1 fixture only}".utf8))
        #expect(ClipboardCapture.read(board, application: "example.fixture", preferences: ClipboardPreferences()) == nil)
        #expect(ClipboardCapture.write(item, to: board, plainText: true))
        #expect(board.pasteboardItems?.first?.data(forType: .rtf) == nil)
        #expect(board.pasteboardItems?[1].string(forType: .fileURL) == "file:///tmp/fixture-one.txt")
    }
    @Test @MainActor func testPrivacyFiltersRunBeforeReadingRepresentations() {
        let board = NSPasteboard(name: NSPasteboard.Name("donyhome-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        for marker in ClipboardCapture.ignored {
            board.clearContents(); let item = NSPasteboardItem(); item.setString("private fixture", forType: .string); item.setString("", forType: NSPasteboard.PasteboardType(marker)); board.writeObjects([item])
            #expect(ClipboardCapture.read(board, application: "example.fixture", preferences: ClipboardPreferences()) == nil)
        }
        board.clearContents(); board.setString("private fixture", forType: .string)
        #expect(ClipboardCapture.read(board, application: "com.1password.1password", preferences: ClipboardPreferences()) == nil)
        var preferences = ClipboardPreferences(); preferences.ignoredApps = ["example.fixture"]
        #expect(ClipboardCapture.read(board, application: "example.fixture", preferences: preferences) == nil)
        preferences.onlyListedApps = true
        #expect(ClipboardCapture.read(board, application: "example.fixture", preferences: preferences) != nil)
        preferences.ignoredPatterns = ["private"]
        #expect(ClipboardCapture.read(board, application: "example.fixture", preferences: preferences) == nil)
        preferences.ignoredPatterns = []; preferences.paused = true
        #expect(ClipboardCapture.read(board, application: "example.fixture", preferences: preferences) == nil)
    }
    @Test func testDuplicateCountsLimitAndPinPreservation() {
        func item(_ text: String) -> ClipboardItem { ClipboardItem(representations: [[ClipboardRepresentation(type: "public.utf8-plain-text", data: Data(text.utf8))]]) }
        var pinned = item("pinned"); pinned.pinned = true
        let older = item("old"), newer = item("new")
        var result = ClipboardHistory.adding(older, to: [pinned], limit: 1)
        result = ClipboardHistory.adding(newer, to: result, limit: 1)
        #expect(Set(result.map(\.id)) == Set([pinned.id, newer.id]))
        result = ClipboardHistory.adding(item("new"), to: result, limit: 1)
        #expect(result.first { $0.id == newer.id }?.numberOfCopies == 2)
        #expect(ClipboardHistory.sorted(result, by: .numberOfCopies).first?.id == pinned.id)
        #expect(ClipboardHistory.search(result, query: "^new$", mode: .regexp).map(\.id) == [newer.id])
        #expect(ClipboardHistory.search(result, query: "[", mode: .regexp).isEmpty)
    }
    @Test func testStoreRoundTripAndCorruptStoreIsNotSilentlyOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("donyhome-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let store = ClipboardStore(url: url)
        #expect(try store.load().isEmpty)
        var item = ClipboardItem(representations: [[ClipboardRepresentation(type: "public.png", data: Data([1, 2, 3]))]])
        item.pinned = true
        try store.save([item]); #expect(try store.load() == [item])
        let malformed = Data("not json fixture".utf8)
        try malformed.write(to: url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: url) == malformed)
    }
    @Test @MainActor func outgoingApplicationIsCheckedBeforeActivationChangesContext() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("donyhome-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let session = ClipboardCaptureSession(pasteboard: board, application: "com.1password.1password")
        board.setString("synthetic password fixture", forType: .string)
        #expect(session.applicationDidActivate("example.allowed", preferences: ClipboardPreferences()) == nil)
        #expect(session.poll(preferences: ClipboardPreferences()) == nil)
        board.clearContents(); board.setString("allowed fixture", forType: .string)
        let item = try #require(session.applicationDidActivate("example.other", preferences: ClipboardPreferences()))
        #expect(item.application == "example.allowed")
        var preferences = ClipboardPreferences(); preferences.ignoredApps = ["example.other"]
        board.clearContents(); board.setString("excluded fixture", forType: .string)
        #expect(session.applicationDidActivate("example.allowed", preferences: preferences) == nil)
    }
    @Test @MainActor func plainTextConvertsRichOnlyDataAndPreservesNonTextRepresentations() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("donyhome-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let rtf = try NSAttributedString(string: "rich fixture").data(from: NSRange(location: 0, length: 12), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        for representation in [ClipboardRepresentation(type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtf), ClipboardRepresentation(type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<b>rich fixture</b>".utf8))] {
            let item = ClipboardItem(representations: [[representation, ClipboardRepresentation(type: NSPasteboard.PasteboardType.png.rawValue, data: Data([1,2,3]))], [ClipboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data("file:///tmp/fixture.txt".utf8))]])
            #expect(ClipboardCapture.write(item, to: board, plainText: true))
            #expect(board.pasteboardItems?.first?.string(forType: .string) == "rich fixture")
            #expect(board.pasteboardItems?.first?.data(forType: .rtf) == nil)
            #expect(board.pasteboardItems?.first?.data(forType: .html) == nil)
            #expect(board.pasteboardItems?.first?.data(forType: .png) == Data([1,2,3]))
            #expect(board.pasteboardItems?[1].string(forType: .fileURL) == "file:///tmp/fixture.txt")
        }
    }
    @Test @MainActor func delayedPasteRejectsReplacedClipboardOrChangedTarget() {
        let board = NSPasteboard(name: NSPasteboard.Name("donyhome-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("selected fixture", forType: .string)
        let ticket = ClipboardPasteTicket(changeCount: board.changeCount, targetProcessIdentifier: 42)
        #expect(ticket.isValid(pasteboard: board, frontmostProcessIdentifier: 42))
        #expect(!ticket.isValid(pasteboard: board, frontmostProcessIdentifier: 43))
        board.clearContents(); board.setString("replacement fixture", forType: .string)
        #expect(!ticket.isValid(pasteboard: board, frontmostProcessIdentifier: 42))
    }
    @Test @MainActor func excludesDerivedRichTextMatchingPrivatePattern() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("donyhome-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let text = "synthetic secret fixture"
        let rtf = try NSAttributedString(string: text).data(from: NSRange(location: 0, length: text.utf16.count), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        var preferences = ClipboardPreferences(); preferences.ignoredPatterns = ["secret"]
        for (type, data) in [(NSPasteboard.PasteboardType.rtf, rtf), (.html, Data("<b>synthetic secret fixture</b>".utf8))] {
            board.clearContents(); let fixture = NSPasteboardItem(); fixture.setData(data, forType: type); board.writeObjects([fixture])
            #expect(ClipboardCapture.read(board, application: "example.fixture", preferences: preferences) == nil)
        }
    }
    @Test func fuzzySearchMatchesUpstreamMaccyReferenceRanking() {
        // MaccyTests/SearchTests.testFuzzySearch uses these exact fixtures with
        // Fuse threshold 0.7: za scores 0.08 (zaz), 0.54 (baz), 0.58 (zzz).
        func item(_ title: String) -> ClipboardItem { ClipboardItem(representations: [[ClipboardRepresentation(type: "public.utf8-plain-text", data: Data(title.utf8))]]) }
        let baz = item("foo bar baz"), zaz = item("foo bar zaz"), zzz = item("xxx yyy zzz")
        let fixtures = [baz, zaz, zzz]
        #expect(ClipboardHistory.search(fixtures, query: "za", mode: .fuzzy).map(\.id) == [zaz.id, baz.id, zzz.id])
        #expect(ClipboardHistory.search(fixtures, query: "z", mode: .fuzzy).map(\.id) == [zaz.id, zzz.id, baz.id])
        #expect(ClipboardHistory.search(fixtures, query: "fbb", mode: .fuzzy).map(\.id) == [baz.id, zaz.id])
        #expect(ClipboardHistory.search(fixtures, query: "m", mode: .fuzzy).isEmpty)
        #expect(ClipboardHistory.search(fixtures, query: "za", mode: .exact).map(\.id) == [zaz.id])
        #expect(ClipboardHistory.search(fixtures, query: "za", mode: .mixed).map(\.id) == [zaz.id])
    }
    @Test @MainActor func pasteQueueCompletionKeepsPreparedClipboardUntilExplicitNextAction() {
        let board = NSPasteboard(name: NSPasteboard.Name("donyhome-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let first = UUID(), next = UUID()
        var queue = ClipboardPasteQueue(itemIDs: [first, next])
        board.setString("first fixture", forType: .string)
        let preparedCount = board.changeCount
        queue.prepare(ticket: ClipboardPasteTicket(changeCount: preparedCount, targetProcessIdentifier: 42))
        let completed = queue.complete(pasteboard: board, frontmostProcessIdentifier: 42)
        #expect(completed)
        #expect(queue.itemIDs == [next])
        #expect(board.changeCount == preparedCount)
        #expect(board.string(forType: .string) == "first fixture")
        let unpreparedCompleted = queue.complete(pasteboard: board, frontmostProcessIdentifier: 42)
        #expect(!unpreparedCompleted, "A second paste cannot consume an unprepared next item")
        board.clearContents(); board.setString("next fixture", forType: .string)
        queue.prepare(ticket: ClipboardPasteTicket(changeCount: board.changeCount, targetProcessIdentifier: 42))
        let changedTargetCompleted = queue.complete(pasteboard: board, frontmostProcessIdentifier: 43)
        #expect(!changedTargetCompleted)
        board.clearContents(); board.setString("external replacement fixture", forType: .string)
        let changedClipboardCompleted = queue.complete(pasteboard: board, frontmostProcessIdentifier: 42)
        #expect(!changedClipboardCompleted)
        #expect(queue.itemIDs == [next])
    }
}
