import SwiftUI
import Foundation
import CryptoKit
import DonyCore
import Darwin

@MainActor final class BatteryController: ObservableObject {
    @Published private(set) var hasBattery = false
    @Published private(set) var supportedArchitecture = false
    @Published private(set) var installed = false
    @Published private(set) var chargingSupported = false
    @Published private(set) var adapterSupported = false
    @Published private(set) var conflict = false
    @Published private(set) var reading = BatteryEngineReading(csv: "")
    @Published private(set) var operation: String?
    @Published var message = "배터리 정보를 확인하고 있어요."
    @Published var log = ""
    @Published private(set) var error: String?
    private var operationID: UUID?
    private var refreshing = false
    var canControl: Bool { hasBattery && supportedArchitecture && installed && chargingSupported }
    var canInstall: Bool { hasBattery && supportedArchitecture && !installed && !conflict && operation == nil }
    private var resources: URL? { Bundle.main.resourceURL?.appendingPathComponent("Battery", isDirectory: true) }
    init() { refresh() }

    private nonisolated static func run(_ executable: String, _ args: [String]) throws -> String {
        let bounded = executable == "/usr/bin/pmset" || executable == "/usr/bin/sudo" || executable.hasSuffix("/smc") || args.first == "status_csv"
        return try BatteryCommandRunner.run(executable, arguments: args,
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "USER": NSUserName(), "LOGNAME": NSUserName()],
            timeout: bounded ? 15 : nil)
    }
    private nonisolated static func trustedFile(_ path: String, hash: String? = nil) -> Bool {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            guard attrs[.type] as? FileAttributeType != .typeSymbolicLink,
                  (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0 else { return false }
            if let hash {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == hash
            }
            return true
        } catch { return false }
    }
    /// 설치 때 남긴 smc 해시(root 소유 파일). 예전 설치본에는 파일이 없어 고정값을 쓴다.
    private nonisolated static func installedSMCHash(base: String) -> String? {
        let file = base + "/smc.sha256"
        guard FileManager.default.fileExists(atPath: file) else { return BatteryInstallation.legacySMCHash }
        guard trustedFile(file), let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        let hash = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.count == 64 && hash.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) ? hash : nil
    }
    private nonisolated static func trustedInstallation() -> Bool {
        let base = BatteryInstallation.directory
        let parents = ["/Library", "/Library/PrivilegedHelperTools", base, "/private", "/private/etc", "/private/etc/sudoers.d"]
        guard parents.allSatisfy({ trustedFile($0) }),
              trustedFile(base + "/battery", hash: BatteryInstallation.engineHash),
              let smcHash = installedSMCHash(base: base),
              trustedFile(base + "/smc", hash: smcHash),
              trustedFile(BatteryInstallation.sudoers),
              trustedFile(base + "/privileges.conf"),
              let expected = try? BatteryInstallation.privilegeConfiguration(user: NSUserName()),
              let actual = try? String(contentsOfFile: base + "/privileges.conf"), actual == expected else { return false }
        return (try? run("/usr/bin/sudo", ["-n", "-l", base + "/smc", "-k", "CH0B", "-w", "00"])) != nil
    }
    private nonisolated static func keyExists(_ key: String) -> Bool {
        guard let text = try? run(BatteryInstallation.directory + "/smc", ["-k", key, "-r"]) else { return false }
        return text.contains(key) && !text.contains("no data") && !text.contains("Error")
    }
    func refresh() {
        guard !refreshing else { return }; refreshing = true
        Task {
            let result = await Task.detached(priority: .utility) { () -> (Bool, Bool, Bool, Bool, Bool, Bool, BatteryEngineReading, String) in
                let power = (try? Self.run("/usr/bin/pmset", ["-g", "batt"])) ?? ""
                let battery = power.contains("InternalBattery")
                var arm: Int32 = 0; var size = MemoryLayout<Int32>.size
                let silicon = sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0 && arm == 1
                let present = Self.trustedInstallation()
                let paths = ["/usr/local/bin/battery", "/usr/local/bin/smc", "/usr/local/co.palokaj.battery", BatteryInstallation.directory, BatteryInstallation.sudoers, NSHomeDirectory() + "/.battery", NSHomeDirectory() + "/Library/LaunchAgents/battery.plist"]
                let conflict = !present && paths.contains { (try? FileManager.default.attributesOfItem(atPath: $0)) != nil }
                let charging = battery && silicon && present && (Self.keyExists("CHTE") || Self.keyExists("CH0B"))
                let adapter = charging && (Self.keyExists("CHIE") || Self.keyExists("CH0I") || Self.keyExists("CH0J"))
                let csv = charging ? ((try? Self.run(BatteryInstallation.executable, ["status_csv"])) ?? "") : ""
                let logs = (try? String(contentsOfFile: NSHomeDirectory() + "/.donyhome-battery/battery.log")) ?? ""
                return (battery, silicon, present, charging, adapter, conflict, BatteryEngineReading(csv: csv), String(logs.suffix(12000)))
            }.value
            hasBattery = result.0; supportedArchitecture = result.1; installed = result.2; chargingSupported = result.3; adapterSupported = result.4; conflict = result.5; reading = result.6; log = result.7; refreshing = false
            if !hasBattery { message = "이 Mac에는 내장 배터리가 없습니다. 배터리 관리 기능은 Apple Silicon MacBook에서 사용할 수 있어요." }
            else if !supportedArchitecture { message = "원본 battery 엔진은 Apple Silicon MacBook을 지원합니다." }
            else if conflict { message = BatteryError.conflict.localizedDescription }
            else if !installed { message = "배터리 제어 도구를 설치하면 충전 한도와 전원 공급을 관리할 수 있어요." }
            else if !chargingSupported { message = "이 Mac의 SMC 충전 제어 키를 확인하지 못했습니다. 제어 기능을 사용할 수 없습니다." }
            else if operation == nil { message = "배터리 상태를 확인했습니다. 유지 설정은 재시동 후에도 적용됩니다." }
        }
    }
    func install() {
        guard canInstall, let resources else { message = "배터리 엔진 리소스를 찾지 못했습니다."; return }
        do {
            let script = try BatteryInstallation.installScript(resources: resources, user: NSUserName())
            let command = "/bin/bash -c " + BatteryInstallation.shellQuote(script)
            let appleString = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
            error = nil; operation = "관리 도구 설치"; message = "macOS 관리자 인증을 진행해 주세요."
            Task {
                do {
                    _ = try await Task.detached { try Self.run("/usr/bin/osascript", ["-e", "do shell script \"\(appleString)\" with administrator privileges"]) }.value
                    message = "배터리 관리 도구를 설치했습니다."
                } catch { self.error = error.localizedDescription; message = error.localizedDescription }
                operation = nil; refresh()
            }
        } catch { self.error = error.localizedDescription; message = error.localizedDescription }
    }
    func execute(_ command: BatteryCommand, title: String) {
        guard canControl else { message = BatteryError.unavailable.localizedDescription; return }
        let needsAdapter: Bool
        switch command { case .adapter, .discharge, .calibrate: needsAdapter = true; case let .maintain(_, _, force): needsAdapter = force; default: needsAdapter = false }
        guard !needsAdapter || adapterSupported else { message = "이 Mac의 어댑터 제어 키를 확인하지 못했습니다."; return }
        guard operation == nil || command == .stop else { return }
        do {
            error = nil; let args = try command.arguments(); let id = UUID(); operationID = id; operation = title
            message = "\(title) 명령을 실행하고 있어요."
            Task {
                do {
                    let output = try await Task.detached {
                        guard Self.trustedInstallation() else { throw BatteryError.untrustedInstallation }
                        return try Self.run(BatteryInstallation.executable, args)
                    }.value
                    if operationID == id {
                        // A returned CLI command alone does not establish hardware success.
                        message = "명령이 종료되었습니다. 현재 배터리 상태와 로그를 확인해 주세요."
                        log = output
                    }
                } catch { if operationID == id { self.error = error.localizedDescription; message = error.localizedDescription } }
                if operationID == id { operation = nil; operationID = nil; refresh() }
            }
        } catch { self.error = error.localizedDescription; message = error.localizedDescription }
    }
    func uninstall() {
        guard canControl, operation == nil else { return }
        do {
            let script = try BatteryInstallation.uninstallScript(user: NSUserName())
            let command = "/bin/bash -c " + BatteryInstallation.shellQuote(script)
            let appleString = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
            error = nil; operation = "배터리 제어 도구 제거"
            message = "유지를 중단하고 충전·어댑터 상태를 복원하고 있어요."
            let requireAdapter = adapterSupported
            Task {
                do {
                    try await Task.detached {
                        guard Self.trustedInstallation() else { throw BatteryError.untrustedInstallation }
                        _ = try Self.run(BatteryInstallation.executable, ["maintain", "stop"])
                        let state = BatteryEngineReading(csv: try Self.run(BatteryInstallation.executable, ["status_csv"]))
                        guard state.charging == true, !requireAdapter || state.discharging == false else {
                            throw BatteryError.failed("충전·어댑터 복원을 확인하지 못해 도구를 제거하지 않았습니다. 상태와 로그를 확인해 주세요.")
                        }
                        _ = try Self.run("/usr/bin/osascript", ["-e", "do shell script \"\(appleString)\" with administrator privileges"])
                        let agent = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents/kr.donyhome.battery.plist")
                        if FileManager.default.fileExists(atPath: agent.path) {
                            let data = try Data(contentsOf: agent)
                            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                            guard plist?["Label"] as? String == "kr.donyhome.battery",
                                  (plist?["ProgramArguments"] as? [String])?.first == BatteryInstallation.executable else {
                                throw BatteryError.failed("제어 도구는 제거했습니다. 변경된 사용자 LaunchAgent는 보존했습니다: " + agent.path)
                            }
                            try FileManager.default.removeItem(at: agent)
                        }
                        // Keep user logs/target preferences; remove only stale runtime markers.
                        for name in ["battery.pid", "operation.pid", "calibrate.pid"] {
                            let marker = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".donyhome-battery/" + name)
                            if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
                        }
                    }.value
                    message = "충전을 복원하고 배터리 제어 도구를 제거했습니다. 사용자 로그와 목표 설정은 보존했습니다."
                } catch { self.error = error.localizedDescription; message = error.localizedDescription }
                operation = nil; refresh()
            }
        } catch { self.error = error.localizedDescription; message = error.localizedDescription }
    }

}
