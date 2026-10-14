import Testing
import Foundation
@testable import DonyCore

@Suite final class RecommendationTests {
    let home: URL
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in ["Caches", "Logs"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/" + name), withIntermediateDirectories: true)
        }
    }
    deinit { try? FileManager.default.removeItem(at: home) }
    func candidate(_ name: String, kind: CandidateKind, age: Double, childAge: Double? = nil) throws -> FileCandidate {
        let root = home.appendingPathComponent(kind == .cache ? "Library/Caches" : "Library/Logs")
        let url = root.appendingPathComponent(name)
        if let childAge {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let child = url.appendingPathComponent("data")
            try Data("fixture".utf8).write(to: child)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-childAge * 86400)], ofItemAtPath: child.path)
        } else { try Data("fixture".utf8).write(to: url) }
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age * 86400)], ofItemAtPath: url.path)
        return try FileCandidate.capture(url: url, root: root, kind: kind)
    }
    @Test func selectsOldKnownCacheButExcludesUnknownRecentAndRunningOwners() throws {
        let policy = CleanupPolicy(home: home)
        let old = try candidate("com.google.Chrome", kind: .cache, age: 20, childAge: 20)
        #expect(try policy.reason(for: old, now: now, runningBundleIDs: []).isRecommended)
        #expect(!(try policy.reason(for: old, now: now, runningBundleIDs: ["com.google.Chrome.helper"])).isRecommended)
        let unknown = try candidate("user-important-data", kind: .cache, age: 100, childAge: 100)
        #expect(!(try policy.reason(for: unknown, now: now, runningBundleIDs: [])).isRecommended)
        let recent = try candidate("com.microsoft.VSCode", kind: .cache, age: 100, childAge: 1)
        #expect(!(try policy.reason(for: recent, now: now, runningBundleIDs: [])).isRecommended)
    }
    @Test func selectsOnlyOldRecognizableLogs() throws {
        let policy = CleanupPolicy(home: home)
        for name in ["old.log", "old.log.1", "old.log.gz"] {
            let file = try candidate(name, kind: .log, age: 40)
            #expect(try policy.reason(for: file, now: now, runningBundleIDs: []).isRecommended)
        }
        for (name, age) in [("recent.log", 1.0), ("notes.txt", 100.0)] {
            let file = try candidate(name, kind: .log, age: age)
            #expect(!(try policy.reason(for: file, now: now, runningBundleIDs: [])).isRecommended)
        }
    }
    @Test func recognizesNestedCacheByItsOwnerRatherThanItsFileName() throws {
        let owner = home.appendingPathComponent("Library/Caches/com.google.Chrome")
        try FileManager.default.createDirectory(at: owner, withIntermediateDirectories: true)
        let file = try candidate("com.google.Chrome/old-data", kind: .cache, age: 20)
        let policy = CleanupPolicy(home: home)
        #expect(try policy.reason(for: file, now: now, runningBundleIDs: []).isRecommended)
        #expect(!(try policy.reason(for: file, now: now, runningBundleIDs: ["com.google.Chrome"])).isRecommended)
    }
    @Test func rejectsChangedCandidateAndCancelledEvaluation() throws {
        let file = try candidate("old.log", kind: .log, age: 40)
        let policy = CleanupPolicy(home: home)
        let token = ScanToken(); token.cancel()
        expectThrows(try policy.reason(for: file, now: now, runningBundleIDs: [], token: token))
        try Data("changed".utf8).write(to: file.url)
        expectThrows(try policy.reason(for: file, now: now, runningBundleIDs: []))
    }
    @Test func refusesOtherRootsAndLinksInsideCaches() throws {
        let file = try candidate("old.log", kind: .log, age: 40)
        #expect(!(try CleanupPolicy().reason(for: file, now: now, runningBundleIDs: [])).isRecommended)
        let directory = home.appendingPathComponent("Library/Caches/com.google.Chrome")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("alias"), withDestinationURL: file.url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-40 * 86400)], ofItemAtPath: directory.path)
        let cache = try FileCandidate.capture(url: directory, root: directory.deletingLastPathComponent(), kind: .cache)
        #expect(!(try CleanupPolicy(home: home).reason(for: cache, now: now, runningBundleIDs: [])).isRecommended)
    }
}

@Suite struct SmartScanTests {
    @Test func singleScanFindsCopiesAndNeverAltersFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["Library/Caches", "Library/Logs", "Downloads"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let downloads = root.appendingPathComponent("Downloads")
        for name in ["original.txt", "copy.txt"] { try Data("identical fixture".utf8).write(to: downloads.appendingPathComponent(name)) }
        let result = SmartScanner.scan(home: root, folder: downloads, runningBundleIDs: [], token: ScanToken(), includeApplications: false)
        #expect(!result.cancelled)
        #expect(result.duplicates.groups.count == 1)
        #expect(result.duplicates.groups[0].copies.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloads.path).count == 2)
    }
    @Test func interruptedScanCannotSupplyRecommendedActions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["Library/Caches", "Library/Logs", "Downloads"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let token = ScanToken()
        let result = SmartScanner.scan(home: root, folder: root.appendingPathComponent("Downloads"), runningBundleIDs: [], token: token, includeApplications: false) { _, phase in
            if phase.hasPrefix("큰 파일") { token.cancel() }
        }
        #expect(result.cancelled)
        #expect(result.recommended.isEmpty)
        #expect(result.duplicates.groups.isEmpty)
    }
}

@Suite struct RecommendedActionTests {
    @Test func recommendedBatchMovesFixtureAndKeepsOriginal() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        for name in ["Library/Caches", "Library/Logs", "Downloads"] { try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true) }
        let log = home.appendingPathComponent("Library/Logs/test.log")
        try Data("disposable old log".utf8).write(to: log)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-40 * 86400)], ofItemAtPath: log.path)
        for name in ["a.txt", "b.txt"] { try Data("disposable duplicate".utf8).write(to: home.appendingPathComponent("Downloads/" + name)) }
        let scan = SmartScanner.scan(home: home, folder: home.appendingPathComponent("Downloads"), runningBundleIDs: [], token: ScanToken(), includeApplications: false)
        let plan = RecommendedActions.plan(cleanup: scan.recommended, duplicates: scan.duplicates.groups)
        #expect(plan.items.count == 2)
        for item in plan.items {
            let action = TrashService.move(item, keeping: plan.originals[item.id])
            #expect(action.success)
            // Restore only this test's disposable file, leaving the user's Trash alone.
            if let path = action.trashPath { try FileManager.default.moveItem(at: URL(fileURLWithPath: path), to: item.url) }
        }
        #expect(FileManager.default.fileExists(atPath: scan.duplicates.groups[0].original.url.path))
    }
    @Test func batchCannotMoveFolderContainingRetainedOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["a", "b"] { try Data("same fixture".utf8).write(to: directory.appendingPathComponent(name)) }
        let parent = try FileCandidate.capture(url: directory, root: root, kind: .cache)
        let group = try #require(DuplicateFinder.find(root: directory, token: ScanToken()).groups.first)
        let plan = RecommendedActions.plan(cleanup: [parent, parent], duplicates: [group])
        #expect(plan.items.count == 1)
        #expect(plan.items[0].id == group.copies[0].id)
        #expect(plan.originals[group.copies[0].id]?.id == group.original.id)
    }
}

@Suite struct ActiveCacheTests {
    @Test func smartScanCannotRecommendDuplicatesInRunningAppCache() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("Library/Caches/com.google.Chrome")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Logs"), withIntermediateDirectories: true)
        for name in ["a", "b"] { try Data("active cache fixture".utf8).write(to: folder.appendingPathComponent(name)) }
        let result = SmartScanner.scan(home: home, folder: folder, runningBundleIDs: ["com.google.Chrome"], token: ScanToken(), includeApplications: false)
        #expect(result.duplicates.groups.isEmpty)
        #expect(result.recommended.isEmpty)
    }
}

@Suite struct DuplicateDependencyTests {
    @Test func duplicateLogRetainsOriginalValidationWhenAlsoCleanupCandidate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["a.log", "b.log"] { try Data("same fixture".utf8).write(to: root.appendingPathComponent(name)) }
        let group = try #require(DuplicateFinder.find(root: root, token: ScanToken()).groups.first)
        let logs = try [group.original.url, group.copies[0].url].map { try FileCandidate.capture(url: $0, root: root, kind: .log) }
        #expect(RecommendedActions.plan(cleanup: logs, duplicates: [group], includeCopies: false).items.isEmpty)
        let plan = RecommendedActions.plan(cleanup: logs, duplicates: [group])
        #expect(plan.items.count == 1)
        #expect(plan.items[0].kind == .duplicate)
        try FileManager.default.removeItem(at: group.original.url)
        let action = TrashService.move(plan.items[0], keeping: plan.originals[plan.items[0].id])
        if let path = action.trashPath { try FileManager.default.moveItem(at: URL(fileURLWithPath: path), to: plan.items[0].url) }
        #expect(!action.success)
        #expect(FileManager.default.fileExists(atPath: group.copies[0].url.path))
    }
}


@Suite struct RecommendationScaleTests {
    @Test func fiftyThousandRegularLeavesArePlannedWithoutPairwiseSearch() {
        let root = URL(fileURLWithPath: "/fixture/cache")
        let leaves = (0..<50_000).map { i in
            FileCandidate(url: root.appendingPathComponent(String(i)), root: root, kind: .cache,
                          fingerprint: FileFingerprint(device: 1, inode: UInt64(i), mode: 0o100644, size: 1, seconds: 0, nanoseconds: 0),
                          anchors: [], bytes: 1, treeStamp: nil)
        }
        let start = Date()
        let plan = RecommendedActions.plan(cleanup: leaves, duplicates: [])
        #expect(plan.items.count == 50_000)
        #expect(plan.bytes == 50_000)
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
