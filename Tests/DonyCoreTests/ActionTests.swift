import Testing
import Foundation
@testable import DonyCore

@Suite final class ActionTests {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    @Test func relatedFilesMatchExactBundleIDOnly() throws {
        let caches = root.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data("yes".utf8).write(to: caches.appendingPathComponent("com.example.app"))
        try Data("no".utf8).write(to: caches.appendingPathComponent("com.example.app.other"))
        let result = ApplicationScanner.relatedFiles(bundleID: "com.example.app", home: root, token: ScanToken())
        expectEqual(result.items.map(\.name), ["com.example.app"])
        expectTrue(result.issues.isEmpty)
    }
    @Test func historyPreservesFailuresAndRealMovedBytes() throws {
        let store = HistoryStore(directory: root)
        let moved = ActionRecord(kind: "휴지통 이동", sourcePath: "/fixture/a", trashPath: "/fixture/trash/a", bytes: 10, success: true, message: "완료")
        let failed = ActionRecord(kind: "휴지통 이동", sourcePath: "/fixture/b", trashPath: nil, bytes: 0, success: false, message: "권한 없음")
        try store.save([moved, failed])
        let loaded = try store.load()
        expectEqual(loaded.count, 2)
        expectEqual(loaded.filter(\.success).reduce(0) { $0 + $1.bytes }, 10)
        expectEqual(loaded.last?.message, "권한 없음")
    }
    @Test func permissionDeniedRelatedFolderIsReported() throws {
        let folder = root.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: folder.appendingPathComponent("com.example.app"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        let result = ApplicationScanner.relatedFiles(bundleID: "com.example.app", home: root, token: ScanToken())
        expectFalse(result.issues.isEmpty)
    }
    @Test func historyFailureRemainsInOperationSummary() {
        let summary = OperationFeedback.compose(summary: "2개 항목을 이동했습니다.", historyError: "디스크가 가득 차서 기록을 저장하지 못했습니다.")
        expectTrue(summary.contains("2개 항목"))
        expectTrue(summary.contains("기록을 저장하지 못했습니다"))
    }
    @Test func corruptHistoryIsReportedWithoutOverwriting() throws {
        let file = root.appendingPathComponent("history.json")
        try Data("invalid json".utf8).write(to: file)
        expectThrows(try HistoryStore(directory: root).load())
        expectEqual(try String(contentsOf: file), "invalid json")
    }
    @Test func trashMovesOnlyDisposableFixtureAndReportsChangedItem() throws {
        let first = root.appendingPathComponent("dony-test-" + UUID().uuidString)
        try Data("disposable fixture".utf8).write(to: first)
        let candidate = try FileCandidate.capture(url: first, root: root, kind: .large)
        let moved = TrashService.move(candidate)
        expectTrue(moved.success)
        expectFalse(FileManager.default.fileExists(atPath: first.path))
        if let trash = moved.trashPath {
            defer { try? FileManager.default.removeItem(atPath: trash) }
            expectTrue(FileManager.default.fileExists(atPath: trash))
            try FileManager.default.moveItem(atPath: trash, toPath: first.path)
        } else { Issue.record("Trash API must return moved fixture location") }
        let stale = try FileCandidate.capture(url: first, root: root, kind: .large)
        try Data("changed".utf8).write(to: first)
        expectFalse(TrashService.move(stale).success)
        expectTrue(FileManager.default.fileExists(atPath: first.path))
    }
}
