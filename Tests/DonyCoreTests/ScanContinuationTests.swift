import Foundation
import Testing
@testable import DonyCore

@Suite struct ScanContinuationTests {
    @Test func continuationIsConsumedOnceAndKeepsScope() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("scope")
        let now = Date()
        ScanContinuation.save(folder: folder, defaults: defaults, now: now)
        #expect(ScanContinuation.take(defaults: defaults, now: now) == folder)
        #expect(ScanContinuation.take(defaults: defaults, now: now) == nil)
    }
    @Test func expiredUnsafeAndCorruptContinuationsDoNotRun() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let now = Date()
        ScanContinuation.save(folder: FileManager.default.temporaryDirectory, defaults: defaults, now: now.addingTimeInterval(-86401))
        #expect(ScanContinuation.take(defaults: defaults, now: now) == nil)
        ScanContinuation.save(folder: URL(fileURLWithPath: "/"), defaults: defaults, now: now)
        #expect(ScanContinuation.take(defaults: defaults, now: now) == nil)
        defaults.set(Data("invalid".utf8), forKey: "pendingFullScan")
        #expect(ScanContinuation.take(defaults: defaults, now: now) == nil)
        #expect(defaults.data(forKey: "pendingFullScan") == nil)
    }
    @Test func preflightSeparatesDeniedMissingAndOtherErrors() {
        let paths = ["/denied", "/missing", "/ok", "/other"].map { URL(fileURLWithPath: $0) }
        let report = FileAccessReport.inspect(paths: paths) { path in
            switch path.path {
            case "/denied": throw NSError(domain: NSPOSIXErrorDomain, code: 13)
            case "/missing": throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
            case "/other": throw NSError(domain: NSPOSIXErrorDomain, code: 5)
            default: break
            }
        }
        #expect(report.checked == 1)
        #expect(report.deniedPaths == ["/denied"])
        #expect(report.issues.count == 2)
    }
}
