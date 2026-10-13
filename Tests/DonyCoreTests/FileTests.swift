import Testing
import Foundation
@testable import DonyCore

@Suite final class FileTests {
    var root: URL!
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func file(_ name: String, contents: String = "a fixture") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
    @Test func testRejectsRootAndPrefixCollision() throws {
        expectThrows(try FileCandidate.capture(url: root, root: root, kind: .large))
        let external = try file("outside")
        expectThrows(try FileCandidate.capture(url: external, root: root.appendingPathComponent("out"), kind: .large))
    }
    @Test func testRejectsSymbolicLinksAndAncestors() throws {
        let real = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: real.appendingPathComponent("file"))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        expectThrows(try FileCandidate.capture(url: link, root: root, kind: .large))
        expectThrows(try FileCandidate.capture(url: link.appendingPathComponent("file"), root: root, kind: .large))
    }
    @Test func testChangedOrReplacedFileCannotBeMoved() throws {
        let url = try file("target")
        let candidate = try FileCandidate.capture(url: url, root: root, kind: .large)
        try Data("changed content".utf8).write(to: url)
        expectThrows(try FileSafety.validate(candidate))
    }
    @Test func testScannerSkipsSymlinkAndFindsSizedFiles() throws {
        _ = try file("big", contents: "1234567890")
        _ = try file("small", contents: "1")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent("big"))
        let result = Scanner.largeFiles(root: root, minimumBytes: 8, token: ScanToken())
        expectEqual(result.items.map { $0.url.lastPathComponent }, ["big"])
        expectEqual(result.items.first?.bytes, 10)
    }
    @Test func testCancelledScanIsReported() throws {
        _ = try file("fixture")
        let token = ScanToken(); token.cancel()
        expectTrue(Scanner.largeFiles(root: root, minimumBytes: 0, token: token).cancelled)
    }
    @Test func testDuplicateFinderPreservesOneOriginalAndSkipsHardlinks() throws {
        let a = try file("a", contents: "same bytes")
        _ = try file("b", contents: "same bytes")
        _ = try file("different", contents: "other data")
        try FileManager.default.linkItem(at: a, to: root.appendingPathComponent("hardlink"))
        let result = DuplicateFinder.find(root: root, token: ScanToken())
        expectEqual(result.groups.count, 1)
        expectEqual(result.groups.first?.copies.count, 1)
        expectEqual(result.groups.first?.bytesRecoverable, 10)
    }
    @Test func testDeletingOrChangingOriginalInvalidatesDuplicate() throws {
        _ = try file("a", contents: "same bytes")
        _ = try file("b", contents: "same bytes")
        let group = try unwrap(DuplicateFinder.find(root: root, token: ScanToken()).groups.first)
        try FileManager.default.removeItem(at: group.original.url)
        expectThrows(try DuplicateFinder.validateCopy(group.copies[0], keeping: group.original, token: ScanToken()))
    }
    @Test func testMissingRootReportsError() {
        let result = Scanner.largeFiles(root: root.appendingPathComponent("missing"), minimumBytes: 0, token: ScanToken())
        expectFalse(result.issues.isEmpty)
    }
    @Test func replacedAncestorWithSymlinkIsRejected() throws {
        let base = root.appendingPathComponent("base")
        let nested = base.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let target = nested.appendingPathComponent("file")
        try Data("fixture".utf8).write(to: target)
        let candidate = try FileCandidate.capture(url: target, root: nested, kind: .large)
        let renamed = root.appendingPathComponent("base-old")
        try FileManager.default.moveItem(at: base, to: renamed)
        try FileManager.default.createSymbolicLink(at: base, withDestinationURL: renamed)
        expectThrows(try FileSafety.validate(candidate))
    }
    @Test func cancellingDuringComparisonReportsCancellationWithoutErrors() throws {
        _ = try file("a", contents: "same bytes")
        _ = try file("b", contents: "same bytes")
        let token = ScanToken()
        let result = DuplicateFinder.find(root: root, token: token) { _, detail in
            if detail.hasPrefix("사본 비교") { token.cancel() }
        }
        expectTrue(result.cancelled)
        expectTrue(result.issues.isEmpty)
    }
}

func expectThrows<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression(); Issue.record("Expected operation to reject invalid input") }
    catch {}
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T) { #expect(actual == expected) }
func expectTrue(_ actual: Bool) { #expect(actual) }
func expectFalse(_ actual: Bool) { #expect(!actual) }
func unwrap<T>(_ value: T?) throws -> T { try #require(value) }
