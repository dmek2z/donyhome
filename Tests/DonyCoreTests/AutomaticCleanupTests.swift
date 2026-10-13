import Testing
import Foundation
@testable import DonyCore

@Suite final class AutomaticCleanupTests {
    let home: URL
    let now = Date()
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for folder in ["Library/Caches/com.google.Chrome", "Library/Caches/unknown", "Library/Logs/Example", "Downloads"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }
    deinit { try? FileManager.default.removeItem(at: home) }
    func file(_ path: String, days: Double) throws -> URL {
        let url = home.appendingPathComponent(path)
        try Data("disposable fixture".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86400)], ofItemAtPath: url.path)
        return url
    }
    @Test func picksOldLeavesWhileKeepingRecentUnknownAndPersonalFiles() throws {
        let oldCache = try file("Library/Caches/com.google.Chrome/old", days: 20)
        let oldLog = try file("Library/Logs/Example/old.log", days: 40)
        let kept = try [file("Library/Caches/com.google.Chrome/recent", days: 1),
                        file("Library/Caches/unknown/old", days: 100),
                        file("Library/Logs/Example/notes.txt", days: 100),
                        file("Downloads/personal.log", days: 100)]
        let result = AutomaticCleanup.scan(home: home, now: now, runningOwners: [], token: ScanToken())
        #expect(!result.cancelled)
        #expect(Set(result.items.map { $0.url.lastPathComponent }) == ["old", "old.log"])
        #expect(result.items.allSatisfy { $0.fingerprint.isRegular })
        // A scan must be read-only, including the files it recommends.
        for url in kept + [oldCache, oldLog] { #expect(FileManager.default.fileExists(atPath: url.path)) }
    }
    @Test func excludesActiveOwnersAndDoesNotFollowLinks() throws {
        _ = try file("Library/Caches/com.google.Chrome/old", days: 20)
        _ = try file("Library/Logs/Example/old.log", days: 40)
        let outside = try file("Downloads/keep.log", days: 100)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Logs/link.log"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Logs/linked-folder"), withDestinationURL: home.appendingPathComponent("Downloads"))
        let result = AutomaticCleanup.scan(home: home, now: now, runningOwners: ["com.google.Chrome.helper", "Example"], token: ScanToken())
        #expect(result.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
    @Test func cancellationDiscardsPartialAutomaticPlan() throws {
        _ = try file("Library/Caches/com.google.Chrome/old", days: 20)
        let token = ScanToken()
        let result = AutomaticCleanup.scan(home: home, now: now, runningOwners: [], token: token) { _, _ in token.cancel() }
        #expect(result.cancelled)
        #expect(result.items.isEmpty)
    }
    @Test func revalidationRefusesAChangedFile() throws {
        let url = try file("Library/Logs/Example/old.log", days: 40)
        let scan = AutomaticCleanup.scan(home: home, now: now, runningOwners: [], token: ScanToken())
        let candidate = try #require(scan.items.first)
        try Data("new log content".utf8).write(to: url)
        expectThrows(try CleanupPolicy(home: home).reason(for: candidate, now: now, runningBundleIDs: []))
        let action = TrashService.move(candidate)
        #expect(!action.success)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
    @Test func dailyScheduleHonorsOptInAndLastAttempt() {
        #expect(!AutomaticCleanup.isDue(enabled: false, lastAttempt: nil, now: now))
        #expect(AutomaticCleanup.isDue(enabled: true, lastAttempt: nil, now: now))
        #expect(!AutomaticCleanup.isDue(enabled: true, lastAttempt: now.addingTimeInterval(-86399), now: now))
        #expect(AutomaticCleanup.isDue(enabled: true, lastAttempt: now.addingTimeInterval(-86400), now: now))
        #expect(!AutomaticCleanup.isDue(enabled: true, lastAttempt: now.addingTimeInterval(3600), now: now))
    }
}
