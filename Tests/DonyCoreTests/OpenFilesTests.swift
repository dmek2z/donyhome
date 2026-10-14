import Foundation
import Testing
@testable import DonyCore

@Suite struct OpenFilesTests {
    @Test func readsAnOwnedFixtureProcessAndProtectsItsOpenFileIdentity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("fixture.log")
        try Data("fixture".utf8).write(to: file)
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        child.arguments = ["-f", "-n", "0", file.path]
        child.standardInput = FileHandle.nullDevice; child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let candidate = try FileCandidate.capture(url: file, root: folder, kind: .log)
        var observed = false
        let deadline = Date().addingTimeInterval(2)
        repeat {
            let readings = SystemSampler().sample().processes.filter { $0.pid == child.processIdentifier }
            if !readings.isEmpty {
                let snapshot = OpenFileSnapshot.read(processes: readings, token: ScanToken(), enumerationComplete: true)
                observed = snapshot.complete && snapshot.contains(candidate)
            }
            if !observed { Thread.sleep(forTimeInterval: 0.02) }
        } while !observed && Date() < deadline
        #expect(observed)
    }
    @Test func aSuppliedSubsetCannotCertifySystemWideCoverage() {
        #expect(!OpenFileSnapshot.read(processes: [], token: ScanToken()).complete)
    }
    @Test func truncatedOwnedInventoryCannotCertifyOpenFiles() {
        let inventory = OwnedProcessInventory.read(capacity: 1)
        #expect(!inventory.complete)
        #expect(!inventory.openFiles(token: ScanToken()).complete)
    }
    @Test func unknownOrCancelledDescriptorReadsStayIncomplete() {
        let token = ScanToken(); token.cancel()
        #expect(!OpenFileSnapshot.read(processes: [], token: token).complete)
    }
}
