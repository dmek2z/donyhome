import Foundation
import Testing
@testable import DonyCore

@Suite final class CacheCoverageTests {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let now = Date()
    init() throws { try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: home) }
    @discardableResult func file(_ path: String, days: Double, bytes: Int = 5) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86400)], ofItemAtPath: url.path)
        return try FileSafety.canonicalRoot(url)
    }
    func scan(days: Int = 14, running: Set<String> = [], token: ScanToken = ScanToken(), limit: Int = 1000) -> CacheCleanupResult {
        CacheCleanup.scan(home: home, runningOwners: running, days: days, token: token, now: now, limit: limit)
    }
    @Test func selectsOldLeavesEvenWhenParentAndNeighborAreRecent() throws {
        let old = try file("Library/Caches/Google/Chrome/Default/Cache/old", days: 20, bytes: 10)
        let recent = try file("Library/Caches/Google/Chrome/Default/Cache/new", days: 1, bytes: 7)
        let result = scan()
        #expect(result.files.items.map(\.id) == [old.path])
        #expect(result.measuredBytes == 17)
        #expect(result.recommendedBytes == 10)
        #expect(result.protectedBytes == 7)
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }
    @Test func configurableRetentionChangesCandidatesAndRevalidation() throws {
        try file("Library/Caches/Aside/old", days: 8)
        #expect(scan(days: 7).files.items.count == 1)
        #expect(scan(days: 14).files.items.isEmpty)
    }
    @Test func detectsNamedElectronCacheButNotAppSupportUserData() throws {
        let cache = try file("Library/Application Support/Slack/Cache/old", days: 40)
        try file("Library/Application Support/Slack/user-data/notes.txt", days: 40)
        try file("Library/Application Support/Slack/Cache/state.db", days: 40)
        #expect(scan().files.items.map(\.id) == [cache.path])
        #expect(scan().measuredBytes == 10)
    }
    @Test func unknownRecentActiveAndCredentialFilesAreNotRecommended() throws {
        try file("Library/Caches/unknown/old", days: 40)
        try file("Library/Caches/Aside/auth.json", days: 40)
        try file("Library/Caches/Aside/old", days: 40)
        #expect(scan(running: ["Aside"]).files.items.isEmpty)
        #expect(scan(running: ["Aside"]).measuredBytes == 15)
    }
    @Test func partialAndCancelledResultsCannotMasqueradeAsComplete() throws {
        for i in 0..<10 { try file("Library/Caches/Aside/\(i)", days: 20) }
        let partial = scan(limit: 3)
        #expect(partial.incomplete)
        #expect(!partial.files.issues.isEmpty)
        let token = ScanToken(); token.cancel()
        let cancelled = scan(token: token)
        #expect(cancelled.files.cancelled)
        #expect(cancelled.files.items.isEmpty)
    }
    @Test func doesNotFollowAliasesOrDoubleCountHardLinks() throws {
        let first = try file("Library/Caches/Aside/one", days: 20)
        try FileManager.default.linkItem(at: first, to: home.appendingPathComponent("Library/Caches/Aside/two"))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/Aside/alias"), withDestinationURL: first)
        let result = scan()
        #expect(result.measuredBytes == 5)
        #expect(result.files.items.count == 1)
    }
    @Test func preservesNestedProjectSourcesAndRechecksOnlyChosenFile() throws {
        let old = try file("Library/Caches/Aside/old", days: 20)
        try file("Library/Caches/Aside/repo/package.json", days: 30)
        try file("Library/Caches/Aside/repo/source.js", days: 30)
        let item = try #require(scan().files.items.first)
        #expect(item.id == old.path)
        let neighbor = try file("Library/Caches/Aside/new", days: 0)
        try FileSafety.validate(item)
        #expect(FileManager.default.fileExists(atPath: neighbor.path))
        try Data("changed".utf8).write(to: old)
        #expect(throws: (any Error).self) { try FileSafety.validate(item) }
    }
    @Test func explicitRetentionIsUsedByAutomaticPolicyAndDeveloperScans() throws {
        let cache = try file("Library/Caches/com.google.Chrome/old", days: 8)
        let automatic = AutomaticCleanup.scan(home: home, now: now, runningOwners: [], token: ScanToken(), days: 7)
        #expect(automatic.items.map(\.id) == [cache.path])
        let candidate = try FileCandidate.capture(url: cache, root: home.appendingPathComponent("Library/Caches"), kind: .cache)
        #expect(try CleanupPolicy(home: home, days: 7).reason(for: candidate, now: now, runningBundleIDs: []).isRecommended)
        #expect(!(try CleanupPolicy(home: home, days: 14).reason(for: candidate, now: now, runningBundleIDs: []).isRecommended))
        let old = try file("Library/Caches/pip/old", days: 8)
        try file("Library/Caches/pip/new", days: 1)
        let developer = DeveloperCleanup.scan(home: home, runningTools: [], token: ScanToken(), now: now, days: 7)
        #expect(developer.recommended.map(\.id) == [old.path])
        #expect(DeveloperCleanup.scan(home: home, runningTools: [], token: ScanToken(), now: now, days: 14).recommended.isEmpty)
    }
    @Test func pnpmMetadataCacheDoesNotSweepThePackageStore() throws {
        let metadata = try file("Library/Caches/pnpm/metadata-v1.3/old.json", days: 30)
        let store = try file("Library/pnpm/store/package/file.js", days: 30)
        let result = DeveloperCleanup.scan(home: home, runningTools: [], token: ScanToken(), now: now, days: 14)
        #expect(result.recommended.map(\.id) == [metadata.path])
        #expect(FileManager.default.fileExists(atPath: store.path))
        let item = try #require(result.recommended.first)
        #expect(throws: (any Error).self) { try DeveloperCleanup.validate(item, home: home, runningTools: [], now: now, days: 60) }
    }

}
