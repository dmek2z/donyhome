import Foundation
import CryptoKit

public enum BatteryCommand: Equatable, Sendable {
    case maintain(Int, lower: Int?, forceDischarge: Bool)
    case voltage(Double, hysteresis: Double)
    case stop, charging(Bool), adapter(Bool), charge(Int), discharge(Int), calibrate
    public func arguments() throws -> [String] {
        func percentage(_ value: Int) throws -> String {
            guard (1...100).contains(value) else { throw BatteryError.invalidTarget }
            return String(value)
        }
        switch self {
        case let .maintain(target, lower, force):
            var level = try percentage(target)
            if let lower {
                guard lower >= 10, lower < target else { throw BatteryError.invalidTarget }
                level = "\(lower)-\(target)"
            }
            return ["maintain", level] + (force ? ["--force-discharge"] : [])
        case let .voltage(value, hysteresis):
            guard value.isFinite, hysteresis.isFinite, (10.5...12.6).contains(value), (0.1...2).contains(hysteresis) else { throw BatteryError.invalidTarget }
            return ["maintain", String(format: "%.2fV", locale: Locale(identifier: "en_US_POSIX"), value), String(format: "%.2fV", locale: Locale(identifier: "en_US_POSIX"), hysteresis)]
        case .stop: return ["maintain", "stop"]
        case let .charging(on): return ["charging", on ? "on" : "off"]
        case let .adapter(on): return ["adapter", on ? "on" : "off"]
        case let .charge(target): return ["charge", try percentage(target)]
        case let .discharge(target): return ["discharge", try percentage(target)]
        case .calibrate: return ["calibrate"]
        }
    }
}
public enum BatteryError: LocalizedError {
    case invalidTarget, unavailable, conflict, untrustedInstallation, failed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidTarget: return "배터리 목표값을 확인해 주세요. 범위는 10–100%, 전압은 10.5–12.6V입니다."
        case .unavailable: return "이 Mac에서는 배터리 관리 엔진을 사용할 수 없습니다."
        case .conflict: return "기존 battery 도구 또는 설치 파일이 있습니다. 기존 설정을 검토하고 백업한 뒤 별도로 정리해 주세요. 자동으로 덮어쓰지 않습니다."
        case .untrustedInstallation: return "설치 파일의 소유권, 권한 또는 무결성을 확인하지 못했습니다."
        case let .failed(message): return message
        }
    }
}
public struct BatteryEngineReading: Equatable, Sendable {
    public var percentage: Int?
    public var remaining: String
    public var charging: Bool?
    public var discharging: Bool?
    public var maintenance: String
    public init(csv: String) {
        let parts = csv.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",")
        percentage = parts.first.flatMap(Int.init).flatMap { (0...100).contains($0) ? $0 : nil }
        remaining = parts.count > 1 ? parts[1] : ""
        func flag(_ index: Int) -> Bool? {
            guard parts.count > index else { return nil }
            switch parts[index].lowercased() { case "enabled", "on", "true", "discharging": return true; case "disabled", "off", "false", "not discharging": return false; default: return nil }
        }
        charging = flag(2); discharging = flag(3)
        maintenance = parts.count > 4 ? parts[4] : ""
    }
}
public enum BatteryInstallation {
    public static let directory = "/Library/PrivilegedHelperTools/donyhome-battery"
    public static let executable = directory + "/battery"
    public static let sudoers = "/private/etc/sudoers.d/donyhome-battery"
    public static let engineHash = "1bf8905c66259c956b62ca3cfbd055902664be663c8cf28d9eb90ed5901ce703"
    /// 미리 빌드한 smc를 쓰던 예전 설치본을 점검·제거하기 위한 값. 새 설치는 smc.sha256 파일을 기준으로 한다.
    public static let legacySMCHash = "2270d5f12a13610e403a6f38f7aab4b3717c2fa8c5c048d303bb2056167fe274"
    /// 앱에 포함된 smc(사용자가 소스에서 빌드한 파일)의 SHA256.
    public static func smcHash(resources: URL) throws -> String {
        guard let data = try? Data(contentsOf: resources.appendingPathComponent("smc")), !data.isEmpty else { throw BatteryError.untrustedInstallation }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func privilegeConfiguration(user: String) throws -> String {
        guard !user.isEmpty, user != "root", user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { throw BatteryError.untrustedInstallation }
        let values = [("CH0B", "02"), ("CH0C", "02"), ("CHTE", "01000000"), ("CH0B", "00"), ("CH0C", "00"), ("CHTE", "00000000"), ("CH0I", "00"), ("CHIE", "00"), ("CH0J", "00"), ("CH0I", "01"), ("CHIE", "08"), ("CH0J", "01"), ("ACLC", "04"), ("ACLC", "03"), ("ACLC", "02"), ("ACLC", "01"), ("ACLC", "00")]
        return "# DonyHome: only fixed battery SMC writes, no shell or updater privileges.\n" + values.map { "\(user) ALL=(root) NOPASSWD: \(directory)/smc -k \($0.0) -w \($0.1)" }.joined(separator: "\n") + "\n"
    }
    /// Complete reviewed offline install body. Never executed by tests or at application launch.
    public static func installScript(resources: URL, user: String) throws -> String {
        let config = try privilegeConfiguration(user: user)
        let smcHash = try Self.smcHash(resources: resources)
        let source = shellQuote(resources.path)
        return """
        set -eu
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        src=\(source)
        dst=\(shellQuote(directory))
        # Refuse foreign installs and every pre-existing destination, including symlinks.
        for p in /usr/local/bin/battery /usr/local/bin/smc /usr/local/co.palokaj.battery "$dst" \(shellQuote(sudoers)); do
          if [ -e "$p" ] || [ -L "$p" ]; then echo '기존 설치를 덮어쓸 수 없습니다.' >&2; exit 1; fi
        done
        for p in /Library /Library/PrivilegedHelperTools /private/etc /private/etc/sudoers.d; do
          if [ -L "$p" ]; then exit 1; fi
          if [ -e "$p" ]; then
            [ "$(/usr/bin/stat -f %u "$p")" = 0 ] || exit 1
            mode=$(/usr/bin/stat -f %Lp "$p")
            [ $((0$mode & 0022)) = 0 ] || exit 1
          fi
        done
        /usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools /private/etc/sudoers.d
        stage=$(/usr/bin/mktemp -d /Library/PrivilegedHelperTools/.donyhome-battery.XXXXXX)
        tmp=$(/usr/bin/mktemp /private/etc/sudoers.d/.donyhome-battery.XXXXXX)
        created=0
        committed=0
        trap '/bin/rm -rf "$stage"; /bin/rm -f "$tmp"; if [ "$created" = 1 ] && [ "$committed" = 0 ]; then /bin/rm -rf "$dst"; fi' EXIT
        /usr/bin/install -o root -g wheel -m 755 "$src/battery" "$stage/battery"
        /usr/bin/install -o root -g wheel -m 755 "$src/smc" "$stage/smc"
        # Validate the root-owned staged bytes, avoiding source hash/copy races.
        [ "$(/usr/bin/shasum -a 256 "$stage/battery" | /usr/bin/awk '{print $1}')" = \(engineHash) ] || exit 1
        [ "$(/usr/bin/shasum -a 256 "$stage/smc" | /usr/bin/awk '{print $1}')" = \(smcHash) ] || exit 1
        # 이 설치에서 검증한 smc의 해시를 root 소유 파일로 남겨 이후 점검·제거의 기준으로 쓴다.
        /usr/bin/printf '%s\n' \(smcHash) > "$stage/smc.sha256"
        /usr/sbin/chown root:wheel "$stage/smc.sha256"
        /bin/chmod 644 "$stage/smc.sha256"
        /usr/bin/printf '%s' \(shellQuote(config)) > "$tmp"
        /usr/bin/install -o root -g wheel -m 644 "$tmp" "$stage/privileges.conf"
        /usr/sbin/chown root:wheel "$tmp"
        /bin/chmod 440 "$tmp"
        /usr/sbin/visudo -cf "$tmp"
        /bin/chmod 755 "$stage"
        /bin/mv "$stage" "$dst"
        created=1
        /bin/mv "$tmp" \(shellQuote(sudoers))
        committed=1
        """
    }
    /// Removes only reviewed app-owned components after the caller restores charging.
    public static func uninstallScript(user: String) throws -> String {
        let config = try privilegeConfiguration(user: user)
        return """
        set -eu
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        dst=\(shellQuote(directory))
        rule=\(shellQuote(sudoers))
        for p in /Library /Library/PrivilegedHelperTools "$dst" /private /private/etc /private/etc/sudoers.d "$rule" "$dst/battery" "$dst/smc" "$dst/privileges.conf"; do
          [ ! -L "$p" ] && [ -e "$p" ] || exit 1
          [ "$(/usr/bin/stat -f %u "$p")" = 0 ] || exit 1
          mode=$(/usr/bin/stat -f %Lp "$p")
          [ $((0$mode & 0022)) = 0 ] || exit 1
        done
        [ "$(/usr/bin/shasum -a 256 "$dst/battery" | /usr/bin/awk '{print $1}')" = \(engineHash) ] || exit 1
        smc_expected=\(legacySMCHash)
        if [ -e "$dst/smc.sha256" ]; then
          [ ! -L "$dst/smc.sha256" ] || exit 1
          [ "$(/usr/bin/stat -f %u "$dst/smc.sha256")" = 0 ] || exit 1
          smc_mode=$(/usr/bin/stat -f %Lp "$dst/smc.sha256")
          [ $((0$smc_mode & 0022)) = 0 ] || exit 1
          smc_expected=$(/bin/cat "$dst/smc.sha256")
          case "$smc_expected" in *[!0-9a-f]*|"") exit 1 ;; esac
          [ "${#smc_expected}" = 64 ] || exit 1
        fi
        [ "$(/usr/bin/shasum -a 256 "$dst/smc" | /usr/bin/awk '{print $1}')" = "$smc_expected" ] || exit 1
        expected=$(/usr/bin/printf '%s' \(shellQuote(config)))
        [ "$(/bin/cat "$rule")" = "$expected" ] || exit 1
        [ "$(/bin/cat "$dst/privileges.conf")" = "$expected" ] || exit 1
        # No recursive deletion: retain unexpected extra files for administrator review.
        /bin/rm -f "$rule" "$dst/battery" "$dst/smc" "$dst/privileges.conf" "$dst/smc.sha256"
        /bin/rmdir "$dst"
        """
    }

}
