import Testing
@testable import DonyCore

@Suite struct RebrandingTests {
    @Test func oldAndNewApplicationProcessNamesStayProtected() {
        for name in ["DonyClean", "DonyHome", "donyhome"] {
            let process = ProcessReading(pid: 100, uid: 501, startSeconds: 1, startMicroseconds: 0, name: name, path: "/Applications/" + name + ".app/Contents/MacOS/" + name, memoryBytes: 100, cpuNanos: nil, cpuPercent: nil)
            #expect(!ProcessPolicy.canQuit(process, currentUID: 501, ownPID: 200, regularApplication: true))
        }
    }
}
