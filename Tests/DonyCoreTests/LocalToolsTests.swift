import Testing
import Foundation
@testable import DonyCore

@Suite final class LocalToolsTests {
    let home: URL
    let now = Date()
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: home) }
    func file(_ relative: String, days: Double = 0, text: String = "local fixture") throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86400)], ofItemAtPath: url.path)
        return url
    }
    func ageDirectory(_ path: String, days: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86400)], ofItemAtPath: home.appendingPathComponent(path).path)
    }
    @Test func developerScanKeepsArchivesAndBlocksRunningOrRecentTools() throws {
        _ = try file("Library/Developer/Xcode/DerivedData/Project-abc/Build/object", days: 10)
        try ageDirectory("Library/Developer/Xcode/DerivedData/Project-abc/Build", days: 10)
        try ageDirectory("Library/Developer/Xcode/DerivedData/Project-abc", days: 10)
        _ = try file("Library/Developer/Xcode/Archives/important.xcarchive/data", days: 100)
        let result = DeveloperCleanup.scan(home: home, runningTools: [], token: ScanToken(), now: now)
        #expect(result.items.count == 1)
        #expect(result.recommended.count == 1)
        #expect(!result.items.contains { $0.id.contains("Archives") })
        #expect(DeveloperCleanup.scan(home: home, runningTools: ["xcodebuild"], token: ScanToken(), now: now).recommended.isEmpty)
        _ = try file("Library/Developer/Xcode/DerivedData/Project-abc/Build/new", days: 0)
        #expect(DeveloperCleanup.scan(home: home, runningTools: [], token: ScanToken(), now: now).recommended.isEmpty)
    }
    @Test func developerScanRejectsLinksAndChangedCandidates() throws {
        let pip = try file("Library/Caches/pip/old", days: 10)
        try ageDirectory("Library/Caches/pip", days: 10)
        let result = DeveloperCleanup.scan(home: home, runningTools: [], token: ScanToken(), now: now)
        let candidate = try #require(result.items.first)
        try Data("changed cache".utf8).write(to: pip)
        expectThrows(try DeveloperCleanup.validate(candidate, home: home, runningTools: [], now: now))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/pip/link"), withDestinationURL: pip)
        #expect(DeveloperCleanup.scan(home: home, runningTools: [], token: ScanToken(), now: now).recommended.isEmpty)
    }
    @Test func leftoversExcludeInstalledRegisteredRunningAppleAndOwnIDs() throws {
        for id in ["com.example.removed", "com.example.installed", "com.example.registered", "com.example.running", "com.apple.finder", "local.dony.DonyClean"] { _ = try file("Library/Preferences/" + id + ".plist") }
        let result = LeftoverScanner.scan(home: home, installedIDs: ["com.example.installed"], runningIDs: ["com.example.running"], registered: { $0 == "com.example.registered" }, token: ScanToken())
        #expect(result.items.map(\.bundleID) == ["com.example.removed"])
    }
    @Test func leftoversRecheckAppInstallationAndFileIdentity() throws {
        _ = try file("Library/Preferences/com.example.removed.plist")
        let result = LeftoverScanner.scan(home: home, installedIDs: [], runningIDs: [], registered: { _ in false }, token: ScanToken())
        let item = try #require(result.items.first)
        expectThrows(try LeftoverScanner.validate(item, installedIDs: [item.bundleID], runningIDs: [], registered: { _ in false }))
        expectThrows(try LeftoverScanner.validate(item, installedIDs: [], runningIDs: [item.bundleID], registered: { _ in false }))
    }
    @Test func clutterSeparatesOldFilesAndInstallersWithoutModifyingThem() throws {
        _ = try file("Downloads/recent.txt")
        let old = try file("Downloads/old.txt", days: 200)
        _ = try file("Downloads/setup.dmg")
        _ = try file("Downloads/installer.pkg")
        let result = ClutterScanner.scan(root: home.appendingPathComponent("Downloads"), token: ScanToken(), now: now)
        #expect(result.oldFiles.items.map(\.name) == ["old.txt"])
        #expect(Set(result.installers.items.map(\.name)) == ["setup.dmg", "installer.pkg"])
        #expect(try String(contentsOf: old) == "local fixture")
    }
    @Test func spaceMapDoesNotFollowLinksOrDoubleCountHardlinks() throws {
        let original = try file("Folder/one/a", text: "1234567890")
        _ = try file("Folder/two/b", text: "12345")
        try FileManager.default.linkItem(at: original, to: home.appendingPathComponent("Folder/two/hardlink"))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Folder/alias"), withDestinationURL: home)
        let result = SpaceMap.scan(root: home.appendingPathComponent("Folder"), token: ScanToken())
        #expect(result.totalBytes == 15)
        #expect(Set(result.entries.map { $0.candidate.name }) == ["one", "two"])
        #expect(result.entries.reduce(0) { $0 + $1.bytes } == 15)
    }
    @Test func newScansReportCancellation() {
        let token = ScanToken(); token.cancel()
        #expect(DeveloperCleanup.scan(home: home, runningTools: [], token: token).cancelled)
        #expect(LeftoverScanner.scan(home: home, installedIDs: [], runningIDs: [], registered: { _ in false }, token: token).cancelled)
        #expect(ClutterScanner.scan(root: home, token: token).oldFiles.cancelled)
        #expect(SpaceMap.scan(root: home, token: token).cancelled)
    }
}

@Suite struct MaintenanceAndMonitorTests {
    @Test func snapshotParserAcceptsOnlyRealSnapshotDates() throws {
        let text = "Snapshots for disk /:\ncom.apple.TimeMachine.2026-10-13-102030.local\ncom.apple.os.update-foo\ncom.apple.TimeMachine.2026-02-30-102030.local\ncom.apple.TimeMachine.2026-10-13-102030.local\n"
        #expect(Maintenance.snapshots(from: text) == ["2026-10-13-102030"])
        expectThrows(try Maintenance.commands(for: .deleteSnapshot("2026-10-13-102030; touch /tmp/pwn")))
        expectThrows(try Maintenance.commands(for: .deleteSnapshot("/")))
        let commands = try Maintenance.commands(for: .deleteSnapshot("2026-10-13-102030"))
        #expect(commands[0].executable == "/usr/bin/tmutil")
        #expect(commands[0].arguments == ["deletelocalsnapshots", "2026-10-13-102030"])
    }
    @Test func fixedMaintenanceCommandsCannotDisableIndexingOrDeleteAllSnapshots() throws {
        let dns = try Maintenance.commands(for: .flushDNS)
        #expect(dns.map(\.executable) == ["/usr/bin/dscacheutil", "/usr/bin/killall"])
        #expect(dns.allSatisfy { $0.requiresAdmin })
        let spotlight = try Maintenance.commands(for: .reindexSpotlight)
        #expect(spotlight[0].arguments == ["-E", "/"])
    }
    @Test func failedMaintenanceIsNotReportedAsSuccess() throws {
        let result = try Maintenance.execute(.flushDNS) { _ in CommandResult(status: 1, output: "permission denied") }
        #expect(!result.success)
        #expect(result.output.contains("permission denied"))
    }
    @Test func networkRatesRejectResetAndInterfaceChanges() {
        let before = NetworkCounters(received: 1000, sent: 2000, generation: 1)
        let current = NetworkCounters(received: 3000, sent: 3000, generation: 1)
        #expect(current.rates(since: before, elapsed: 2)?.received == 1000)
        #expect(current.rates(since: before, elapsed: 2)?.sent == 500)
        #expect(NetworkCounters(received: 1, sent: 1, generation: 1).rates(since: before, elapsed: 2) == nil)
        #expect(NetworkCounters(received: 5000, sent: 6000, generation: 2).rates(since: before, elapsed: 2) == nil)
    }
    @Test func batteryUnavailableDoesNotBecomeZeroPercent() {
        #expect(BatteryReading.parse([:]) == nil)
        #expect(BatteryReading.parse(["Current Capacity": 10, "Max Capacity": 0]) == nil)
        #expect(BatteryReading.parse(["Current Capacity": 60, "Max Capacity": 100, "Is Charging": true, "Power Source State": "AC Power"])?.percent == 60)
    }
}

@Suite struct LocalIntegrationTests {
    @Test func smartScanIncludesDeveloperClutterLeftoversAndSpace() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        for relative in ["Library/Logs", "Library/Caches/pip", "Library/Preferences", "Downloads"] { try FileManager.default.createDirectory(at: home.appendingPathComponent(relative), withIntermediateDirectories: true) }
        let pip = home.appendingPathComponent("Library/Caches/pip/package")
        try Data("cache fixture".utf8).write(to: pip)
        for path in [pip.path, home.appendingPathComponent("Library/Caches/pip").path] { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 86400)], ofItemAtPath: path) }
        try Data("orphan fixture".utf8).write(to: home.appendingPathComponent("Library/Preferences/com.donyfixture.removed.plist"))
        let old = home.appendingPathComponent("Downloads/setup.dmg")
        try Data("installer fixture".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-200 * 86400)], ofItemAtPath: old.path)
        let result = SmartScanner.scan(home: home, folder: home.appendingPathComponent("Downloads"), runningBundleIDs: [], runningTools: [], token: ScanToken(), includeApplications: false)
        #expect(!result.cancelled)
        #expect(result.developer.recommended.count == 1)
        #expect(result.clutter.oldFiles.items.count == 1)
        #expect(result.clutter.installers.items.count == 1)
        #expect(result.leftovers.items.count == 1)
        #expect(result.space.totalBytes == 17)
        let item = try #require(result.developer.recommended.first)
        try DeveloperCleanup.validate(item, home: home, runningTools: [])
        let action = TrashService.move(item)
        #expect(action.success)
        if let path = action.trashPath { try FileManager.default.moveItem(at: URL(fileURLWithPath: path), to: item.url) }
        #expect(FileManager.default.fileExists(atPath: old.path))
    }
    @Test func unreadableDeveloperAndLeftoverRootsReportIssues() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.appendingPathComponent("Library").path); try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library"), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home.appendingPathComponent("Library").path)
        #expect(!DeveloperCleanup.scan(home: home, runningTools: [], token: ScanToken()).issues.isEmpty)
        #expect(!LeftoverScanner.scan(home: home, installedIDs: [], runningIDs: [], registered: { _ in false }, token: ScanToken()).issues.isEmpty)
    }
}

@Suite struct LocalSafetyRegressionTests {
    @Test func derivedDataRecommendationPreservesPackageRepositories() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Project-abc")
        let build = project.appendingPathComponent("Build")
        let repo = project.appendingPathComponent("SourcePackages/checkouts/Package/.git")
        for directory in [build, repo] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        try Data("compiled fixture".utf8).write(to: build.appendingPathComponent("object"))
        try Data("local source edits".utf8).write(to: repo.appendingPathComponent("config"))
        let iterator = FileManager.default.enumerator(at: project, includingPropertiesForKeys: nil)!
        for case let url as URL in iterator { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 86400)], ofItemAtPath: url.path) }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 86400)], ofItemAtPath: project.path)
        let result = DeveloperCleanup.scan(home: home, runningTools: [], token: ScanToken())
        #expect(!result.recommended.isEmpty)
        #expect(result.recommended.allSatisfy { $0.name == "Build" })
        let parent = try FileCandidate.capture(url: project, root: project.deletingLastPathComponent(), kind: .developer)
        expectThrows(try DeveloperCleanup.validate(parent, home: home, runningTools: []))
        #expect(try String(contentsOf: repo.appendingPathComponent("config")) == "local source edits")
    }
    @Test func cloudPlaceholdersCannotBecomeSelectableMapItems() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder"), withIntermediateDirectories: true)
        let placeholder = root.appendingPathComponent("placeholder")
        let nested = root.appendingPathComponent("folder/cloud")
        try Data("placeholder fixture".utf8).write(to: placeholder)
        try Data("nested fixture".utf8).write(to: nested)
        let metadata: @Sendable (URL) throws -> Bool = { $0.lastPathComponent == "placeholder" || $0.lastPathComponent == "cloud" }
        let result = SpaceMap.scan(root: root, token: ScanToken(), isPlaceholder: metadata)
        #expect(!result.entries.contains { $0.candidate.name == "placeholder" })
        let folder = try #require(result.entries.first { $0.candidate.name == "folder" })
        #expect(!folder.selectable)
        expectThrows(try SpaceMap.validateSelection(folder.candidate, isPlaceholder: metadata))
    }
    @Test func cancellingAfterWalkCancelsBothClutterCategories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("installer fixture".utf8).write(to: root.appendingPathComponent("setup.dmg"))
        let token = ScanToken()
        let result = ClutterScanner.scan(root: root, token: token) { _, phase in if phase == "완료" { token.cancel() } }
        #expect(result.oldFiles.cancelled)
        #expect(result.installers.cancelled)
        expectThrows(try FileCandidate.capture(url: root.appendingPathComponent("setup.dmg"), root: root, kind: .installer, token: token))
    }
}
