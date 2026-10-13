import Testing
import Foundation
@testable import DonyCore

@Suite struct TrashEmptyTests {
    @Test func onlyCapturedFixtureItemsAreRemovedAndNewItemsRemain() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let trash = home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("disposable".utf8).write(to: trash.appendingPathComponent("old"))
        let scan = TrashEmptyService.scan(home: home, token: ScanToken())
        #expect(scan.items.count == 1)
        try Data("new fixture".utf8).write(to: trash.appendingPathComponent("new"))
        let result = TrashEmptyService.remove(scan.items[0], home: home)
        #expect(result.success)
        #expect(!FileManager.default.fileExists(atPath: trash.appendingPathComponent("old").path))
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("new").path))
    }
    @Test func changedItemsAndTrashRootSymlinksAreRejected() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let trash = home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let target = trash.appendingPathComponent("fixture")
        try Data("before".utf8).write(to: target)
        let scan = TrashEmptyService.scan(home: home, token: ScanToken())
        try Data("changed data".utf8).write(to: target)
        #expect(!TrashEmptyService.remove(scan.items[0], home: home).success)
        let renamed = home.appendingPathComponent("saved-trash")
        try FileManager.default.moveItem(at: trash, to: renamed)
        try FileManager.default.createSymbolicLink(at: trash, withDestinationURL: renamed)
        #expect(TrashEmptyService.scan(home: home, token: ScanToken()).items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: renamed.appendingPathComponent("fixture").path))
    }
    @Test func nestedLinksDoNotRemoveTheirTargets() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent(".Trash/folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outside = home.appendingPathComponent("retained")
        try Data("kept fixture".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: outside)
        let scan = TrashEmptyService.scan(home: home, token: ScanToken())
        #expect(TrashEmptyService.remove(scan.items[0], home: home).success)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}
