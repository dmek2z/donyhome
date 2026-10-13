import Testing
import Foundation
@testable import DonyCore

@Suite struct BatteryTests {
    @Test func mapsEveryOriginalHardwareAction() throws {
        #expect(try BatteryCommand.maintain(80, lower: nil, forceDischarge: false).arguments() == ["maintain", "80"])
        #expect(try BatteryCommand.maintain(80, lower: 70, forceDischarge: true).arguments() == ["maintain", "70-80", "--force-discharge"])
        #expect(try BatteryCommand.voltage(11.4, hysteresis: 0.3).arguments() == ["maintain", "11.40V", "0.30V"])
        #expect(try BatteryCommand.stop.arguments() == ["maintain", "stop"])
        #expect(try BatteryCommand.charging(false).arguments() == ["charging", "off"])
        #expect(try BatteryCommand.adapter(true).arguments() == ["adapter", "on"])
        #expect(try BatteryCommand.charge(90).arguments() == ["charge", "90"])
        #expect(try BatteryCommand.discharge(20).arguments() == ["discharge", "20"])
        #expect(try BatteryCommand.calibrate.arguments() == ["calibrate"])
    }
    @Test func rejectsInvalidTargetsBeforeInvocation() {
        let commands: [BatteryCommand] = [.maintain(101, lower: nil, forceDischarge: false), .maintain(80, lower: 80, forceDischarge: false), .maintain(80, lower: 9, forceDischarge: false), .charge(0), .discharge(-1), .voltage(.nan, hysteresis: 0.1), .voltage(10, hysteresis: 0.1), .voltage(11.4, hysteresis: 3)]
        for command in commands { #expect(throws: BatteryError.self) { try command.arguments() } }
    }
    @Test func statusDoesNotFabricateMissingValues() {
        #expect(BatteryEngineReading(csv: "").percentage == nil)
        #expect(BatteryEngineReading(csv: "garbage").charging == nil)
        #expect(BatteryEngineReading(csv: "101,unknown,unknown,unknown,").percentage == nil)
        let reading = BatteryEngineReading(csv: "80,2:10,disabled,enabled,70-80\n")
        #expect(reading.percentage == 80)
        #expect(reading.charging == false)
        #expect(reading.discharging == true)
        #expect(reading.maintenance == "70-80")
    }
    @Test func privilegeConfigurationIsUserScopedAndHasNoUpdaterOrShell() throws {
        let config = try BatteryInstallation.privilegeConfiguration(user: "dony")
        let lines = config.split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(lines.count == 17)
        #expect(lines.allSatisfy { $0.hasPrefix("dony ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/donyhome-battery/smc -k ") })
        let rules = lines.joined(separator: "\n")
        #expect(!rules.contains("update"))
        #expect(!rules.contains("/bin/bash"))
        #expect(!rules.contains("ALL ALL"))
        #expect(!rules.contains("*"))
        let permittedWrites: Set<String> = ["CH0B 02", "CH0C 02", "CHTE 01000000", "CH0B 00", "CH0C 00", "CHTE 00000000", "CH0I 00", "CHIE 00", "CH0J 00", "CH0I 01", "CHIE 08", "CH0J 01", "ACLC 04", "ACLC 03", "ACLC 02", "ACLC 01", "ACLC 00"]
        var actualWrites = Set<String>()
        for line in lines {
            let tokens = line.split(separator: " ")
            #expect(tokens.count == 8)
            guard tokens.count == 8 else { continue }
            #expect(tokens[4] == "-k" && tokens[6] == "-w")
            actualWrites.insert("\(tokens[5]) \(tokens[7])")
        }
        #expect(actualWrites == permittedWrites)
        #expect(throws: BatteryError.self) { try BatteryInstallation.privilegeConfiguration(user: "x\nALL ALL=(ALL) NOPASSWD: ALL") }
        #expect(throws: BatteryError.self) { try BatteryInstallation.privilegeConfiguration(user: "root") }
    }
    @Test func offlineInstallQuotesResourcePathAndChecksStagedHashes() throws {
        #expect(BatteryInstallation.shellQuote("a'b $(touch x)") == "'a'\\''b $(touch x)'")
        let path = URL(fileURLWithPath: "/Applications/A ' $(x)/Contents/Resources/Battery")
        let script = try BatteryInstallation.installScript(resources: path, user: "dony")
        #expect(script.contains("src=" + BatteryInstallation.shellQuote(path.path)))
        #expect(script.contains("shasum -a 256 \"$stage/battery\""))
        #expect(script.contains(BatteryInstallation.engineHash))
        #expect(script.contains("visudo -cf"))
        #expect(script.contains("[ -L \"$p\" ]"))
        #expect(!script.contains("curl"))
        #expect(!script.contains("charging on"))
        #expect(!script.contains("$src/setup.sh"))
    }
    @Test func parsesOriginalAdapterStatusWords() {
        #expect(BatteryEngineReading(csv: "80,unknown,enabled,not discharging,80").discharging == false)
        #expect(BatteryEngineReading(csv: "80,unknown,disabled,discharging,80").discharging == true)
    }
    @Test func removalValidatesOwnedBytesAndNeverRecursivelyDeletes() throws {
        let script = try BatteryInstallation.uninstallScript(user: "dony")
        let deletion = script.split(separator: "\n").filter { $0.contains("/bin/rm") }
        #expect(deletion.count == 2)
        #expect(deletion.contains { $0.contains("/bin/rm -f \"$rule\" \"$dst/battery\" \"$dst/smc\" \"$dst/privileges.conf\"") })
        #expect(deletion.contains { $0.contains("/bin/rmdir \"$dst\"") })
        #expect(!script.contains("rm -rf"))
        #expect(!script.contains("/usr/local/bin"))
        #expect(!script.contains("curl"))
        #expect(script.contains(BatteryInstallation.engineHash))
        #expect(script.contains(BatteryInstallation.smcHash))
        #expect(script.contains("[ ! -L \"$p\" ]"))
        #expect(script.contains("$(/bin/cat \"$rule\")"))
        #expect(throws: BatteryError.self) { try BatteryInstallation.uninstallScript(user: "x;rm -rf /") }
    }

    @Test func commandDoesNotWaitForDetachedChildStderrToClose() throws {
        let start = Date()
        // A harmless short-lived subprocess reproduces an inherited stderr descriptor.
        let output = try BatteryCommandRunner.run("/bin/sh", arguments: ["-c", "sleep 3 >&2 & printf foreground-finished"], timeout: 1)
        #expect(output.contains("foreground-finished"))
        #expect(Date().timeIntervalSince(start) < 2)
    }
    @Test func boundedProbeTerminatesOnTimeout() {
        let start = Date()
        #expect(throws: BatteryError.self) {
            try BatteryCommandRunner.run("/bin/sleep", arguments: ["3"], timeout: 0.1)
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }

}
