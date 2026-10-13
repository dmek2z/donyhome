import Foundation
import Testing
@testable import DonyCore

@Suite struct CharacterAndPermissionTests {
    @Test func emptySizesUseNumericZero() {
        #expect(DisplayFormat.bytes(0) == "0 B")
        #expect(DisplayFormat.bytes(-1) == "0 B")
    }
    @Test func characterPaceTracksCPUAndMemoryPressure() {
        #expect(CharacterActivity.resolve(cpu: 0, pressure: .normal) == .relaxed)
        #expect(CharacterActivity.resolve(cpu: 49, pressure: .normal) == .relaxed)
        #expect(CharacterActivity.resolve(cpu: 50, pressure: .normal) == .working)
        #expect(CharacterActivity.resolve(cpu: 85, pressure: .normal) == .overloaded)
        #expect(CharacterActivity.resolve(cpu: nil, pressure: .warning) == .working)
        #expect(CharacterActivity.resolve(cpu: nil, pressure: .critical) == .overloaded)
        #expect(CharacterActivity.overloaded.interval < CharacterActivity.relaxed.interval)
    }
    @Test func permissionErrorsDistinguishProtectedFilesFromOtherSkips() {
        let denied = NSError(domain: NSPOSIXErrorDomain, code: 13)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSUnderlyingErrorKey: denied])
        #expect(ScanIssue(path: "/private", error: wrapped).permissionDenied == true)
        #expect(ScanIssue(path: "/private", error: NSError(domain: NSCocoaErrorDomain, code: 257)).permissionDenied == true)
        #expect(ScanIssue(path: "/missing", error: NSError(domain: NSPOSIXErrorDomain, code: 2)).permissionDenied == false)
        #expect(ScanIssue(path: "/busy", message: "사용 중인 앱").permissionDenied != true)
    }
    @Test func legacyScanIssuesRemainDecodable() throws {
        let issue = try JSONDecoder().decode(ScanIssue.self, from: Data(#"{"path":"/test","message":"skip"}"#.utf8))
        #expect(issue.permissionDenied == nil)
    }
    @Test func unresponsiveSystemCacheIsExcludedWithoutClaimingPermissionDenial() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("com.apple.Music")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        try Data("preserve".utf8).write(to: music.appendingPathComponent("test"))
        let result = Scanner.cleanup(roots: [(root, .cache)], token: ScanToken())
        #expect(result.items.isEmpty)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].permissionDenied != true)
        #expect(try String(contentsOf: music.appendingPathComponent("test")) == "preserve")
    }
}
