import Testing
import Foundation
@testable import DonyCore

private final class SmartPhaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SmartScanPhase] = []
    func append(_ phase: SmartScanPhase) { lock.lock(); recorded.append(phase); lock.unlock() }
    var phases: [SmartScanPhase] { lock.lock(); defer { lock.unlock() }; return recorded }
}

@Suite struct SmartScanPhaseTests {
    private func fixture() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("donyhome-smart-phases-" + UUID().uuidString)
        for path in ["Library/Caches", "Library/Logs", "Downloads", ".Trash"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try Data("phase fixture only".utf8).write(to: home.appendingPathComponent("Downloads/sample.txt"))
        return home
    }
    @Test func reportsActualOrderedPhasesAndCompletionForFixtureScan() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let recorder = SmartPhaseRecorder()
        let result = SmartScanner.scan(home: home, folder: home.appendingPathComponent("Downloads"), runningBundleIDs: [], runningTools: [], token: ScanToken(), includeApplications: false, phase: { recorder.append($0) })
        #expect(recorder.phases == [.cleanup, .development, .files, .applications, .space, .photos, .trash, .complete])
        #expect(!result.cancelled)
        #expect(result.applications.apps.isEmpty, "Installed-app inventory is disabled; application-related fixture files still have a real phase")
        #expect(try Data(contentsOf: home.appendingPathComponent("Downloads/sample.txt")) == Data("phase fixture only".utf8))
    }
    @Test func cancellationAtDevelopmentStopsSubsequentPhaseCallbacks() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let recorder = SmartPhaseRecorder(), token = ScanToken()
        let result = SmartScanner.scan(home: home, folder: home.appendingPathComponent("Downloads"), runningBundleIDs: [], runningTools: [], token: token, includeApplications: false, phase: { phase in
            recorder.append(phase)
            if phase == .development { token.cancel() }
        })
        #expect(recorder.phases == [.cleanup, .development])
        #expect(result.cancelled)
        #expect(result.recommended.isEmpty)
        #expect(result.largeFiles.items.isEmpty)
    }
    @Test func alreadyCancelledScanReportsNoStartedOrCompletedPhases() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let recorder = SmartPhaseRecorder(), token = ScanToken(); token.cancel()
        let result = SmartScanner.scan(home: home, folder: home.appendingPathComponent("Downloads"), runningBundleIDs: [], runningTools: [], token: token, includeApplications: false, phase: { recorder.append($0) })
        #expect(recorder.phases.isEmpty)
        #expect(result.cancelled)
        #expect(result.recommended.isEmpty)
    }
    @Test func cancellationInFinalPhaseDoesNotEmitComplete() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let recorder = SmartPhaseRecorder(), token = ScanToken()
        let result = SmartScanner.scan(home: home, folder: home.appendingPathComponent("Downloads"), runningBundleIDs: [], runningTools: [], token: token, includeApplications: false, phase: { phase in
            recorder.append(phase)
            if phase == .trash { token.cancel() }
        })
        #expect(recorder.phases.last == .trash)
        #expect(!recorder.phases.contains(.complete))
        #expect(result.cancelled)
    }
}
