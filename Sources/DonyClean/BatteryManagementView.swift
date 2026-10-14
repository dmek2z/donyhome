import SwiftUI
import AppKit
import DonyCore

struct BatteryManagementView: View {
    @StateObject private var battery = BatteryController()
    @State private var mode = "충전 한도"
    @State private var target = 80
    @State private var lower = 70
    @State private var forceDischarge = false
    @State private var voltage = 11.4
    @State private var hysteresis = 0.1
    @State private var manualTarget = 80
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private var idle: Bool { battery.canControl && battery.operation == nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "배터리 관리")
                HStack(alignment: .top, spacing: 20) {
                    DonyIcon("battery.75percent", size: 30).foregroundStyle(Theme.primary).frame(width: 64, height: 64).background(Theme.blueWash).clipShape(RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(battery.hasBattery ? battery.reading.percentage.map { "현재 배터리 \($0)%" } ?? "배터리 상태 확인" : "내장 배터리가 없는 Mac").font(Theme.font(22, weight: .bold))
                        Text(battery.error ?? battery.message).font(Theme.font(14)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        if battery.installed && battery.hasBattery {
                            HStack(spacing: 8) {
                                Chip(text: battery.reading.charging.map { $0 ? "충전 허용" : "충전 차단" } ?? "충전 상태 미확인")
                                if !battery.reading.maintenance.isEmpty { Chip(text: "유지 \(battery.reading.maintenance)") }
                                if battery.reading.discharging == true { Chip(text: "어댑터 공급 차단", color: Theme.amber) }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Button("새로고침") { battery.refresh() }.buttonStyle(QuietButton())
                }.panel()

                if battery.hasBattery && battery.supportedArchitecture {
                if !battery.installed {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsActionRow(title: "배터리 제어 도구", actionTitle: "설치 검토", enabled: battery.canInstall) { Task { await reviewInstallation() } }
                        Text("검토한 battery 엔진을 이 앱 전용 위치에 설치합니다. macOS 관리자 인증이 필요하며, 기존 battery 도구가 있으면 설치를 중단합니다.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                    }.panel()
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text("충전 유지").font(Theme.font(18, weight: .semibold))
                    DonyChoices(options: ["충전 한도", "충전 범위", "전압 유지"], selection: $mode).frame(maxWidth: 430)
                    if mode == "전압 유지" {
                        HStack {
                            Text("목표 전압").font(Theme.font(14)); Spacer()
                            Stepper(value: $voltage, in: 10.5...12.6, step: 0.1) { Text(String(format: "%.1f V", voltage)).frame(width: 80) }.frame(width: 180)
                        }
                        HStack {
                            Text("전압 허용 범위").font(Theme.font(14)); Spacer()
                            Stepper(value: $hysteresis, in: 0.1...2, step: 0.1) { Text(String(format: "± %.1f V", hysteresis)).frame(width: 80) }.frame(width: 180)
                        }
                    } else {
                        percentRow(mode == "충전 범위" ? "상한" : "충전 한도", value: $target, range: 1...100)
                        if mode == "충전 범위" { percentRow("하한", value: $lower, range: 10...99) }
                        Toggle("목표보다 높으면 어댑터를 차단해 방전", isOn: $forceDischarge).toggleStyle(DonySwitch()).disabled(!battery.adapterSupported)
                        if forceDischarge { Text("덮개를 닫은 상태에서는 강제 방전이 안정적으로 작동하지 않을 수 있어요.").font(Theme.font(12)).foregroundStyle(Theme.amber) }
                    }
                    HStack {
                        Text("재시동 후에도 원본 엔진이 설정을 유지합니다.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("유지 시작") {
                            let command: BatteryCommand = mode == "전압 유지" ? .voltage(voltage, hysteresis: hysteresis) : .maintain(target, lower: mode == "충전 범위" ? lower : nil, forceDischarge: forceDischarge)
                            battery.execute(command, title: "충전 유지 시작")
                        }.buttonStyle(PrimaryButton()).disabled(!idle)
                    }
                }.panel().disabled(!battery.canControl)

                DisclosureGroup("수동 제어") {
                  VStack(alignment: .leading, spacing: 20) {
                    Text("수동 제어는 현재 유지 설정을 중단합니다. 목표 충전·방전과 보정이 끝나면 원래 유지 설정을 복원합니다.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                    SettingsActionRow(title: "유지 · 진행 중 작업 중단", actionTitle: "중단", enabled: battery.canControl) { battery.execute(.stop, title: "중단 및 충전 복원") }
                    commandRow("배터리 충전", on: .charging(true), off: .charging(false), enabled: idle)
                    commandRow("어댑터 전원 공급", on: .adapter(true), off: .adapter(false), enabled: idle && battery.adapterSupported)
                    percentRow("일회성 목표", value: $manualTarget, range: 1...100).disabled(!idle)
                    HStack {
                        Text("목표 배터리까지").font(Theme.font(14)); Spacer()
                        Button("충전") { battery.execute(.charge(manualTarget), title: "목표까지 충전") }.buttonStyle(QuietButton()).disabled(!idle)
                        Button("방전") { battery.execute(.discharge(manualTarget), title: "목표까지 방전") }.buttonStyle(QuietButton()).disabled(!idle || !battery.adapterSupported)
                    }
                    SettingsActionRow(title: "배터리 보정", actionTitle: "보정 검토", enabled: idle && battery.adapterSupported) { Task { await reviewCalibration() } }
                    if let operation = battery.operation { HStack { ProgressView().controlSize(.small); Text(operation).font(Theme.font(13)) } }
                  }.padding(.top, 16)
                }.font(Theme.font(16, weight: .semibold)).tint(Theme.secondary).panel()
                if battery.installed {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsActionRow(title: "배터리 제어 도구 제거", actionTitle: "제거 검토", enabled: idle) { Task { await reviewRemoval() } }
                        Text("충전과 어댑터 공급을 복원한 뒤 앱 전용 도구·권한·유지 LaunchAgent를 제거합니다. 로그와 목표 설정은 보존합니다.").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                    }.panel()
                }
                DisclosureGroup("원본 엔진 로그 · 라이선스") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(battery.log.isEmpty ? "아직 엔진 로그가 없습니다." : battery.log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Link("원본 battery 프로젝트 (MIT)", destination: URL(string: "https://github.com/actuallymentor/battery")!)
                        Text("battery v1.3.4 · 앱 전용 오프라인 통합. SMC 도구: smcFanControl (GPL v2). 원본, 수정 엔진, SMC 소스와 라이선스가 앱에 포함되어 있습니다.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        Button("소스 · 라이선스 폴더 열기") {
                            if let url = Bundle.main.resourceURL?.appendingPathComponent("Battery") { NSWorkspace.shared.open(url) }
                        }.buttonStyle(QuietButton())
                    }.padding(.top, 12)
                }.font(Theme.font(14)).panel()
                }
        }.background(Theme.canvas)
            .onReceive(timer) { _ in battery.refresh() }
    }
    @MainActor private func reviewInstallation() async {
        let paths = [BatteryInstallation.directory + "/battery", BatteryInstallation.directory + "/smc", BatteryInstallation.directory + "/privileges.conf", BatteryInstallation.sudoers, NSHomeDirectory() + "/Library/LaunchAgents/kr.donyhome.battery.plist"]
        if await ConfirmationDialog.show(title: "배터리 제어 도구 설치", message: "포함된 오프라인 엔진과 SMC 도구를 root 소유로 설치합니다. 현재 사용자에게 지정된 17개 배터리 SMC 쓰기 명령만 암호 없이 허용합니다. 유지 시작 시 LaunchAgent가 재시동 뒤에도 설정을 적용합니다. 기존 도구는 덮어쓰지 않으며, 다음 단계에서 macOS 관리자 인증을 요청합니다.", action: "관리자 인증 후 설치", destructive: true, paths: paths) {
            guard battery.canInstall else { return }
            battery.install()
        }
    }
    @MainActor private func reviewCalibration() async {
        if await ConfirmationDialog.show(title: "배터리 보정을 시작할까요?", message: "원본 순서: 15%까지 방전 → 100% 충전 → 1시간 유지 → 80%까지 방전 → 기존 유지 설정 복원. 여러 시간이 걸리며 어댑터가 연결되어 있어야 합니다. 중단 버튼으로 종료하고 충전을 복원할 수 있어요.", action: "보정 시작", destructive: true, paths: []) {
            guard idle, battery.adapterSupported else { return }
            battery.execute(.calibrate, title: "배터리 보정")
        }
    }
    @MainActor private func reviewRemoval() async {
        let paths = [BatteryInstallation.directory + "/battery", BatteryInstallation.directory + "/smc", BatteryInstallation.directory + "/privileges.conf", BatteryInstallation.sudoers, NSHomeDirectory() + "/Library/LaunchAgents/kr.donyhome.battery.plist"] + ["battery.pid", "operation.pid", "calibrate.pid"].map { NSHomeDirectory() + "/.donyhome-battery/" + $0 }
        if await ConfirmationDialog.show(title: "배터리 제어 도구를 제거할까요?", message: "먼저 유지·방전을 중단하고 충전과 어댑터 공급 복원을 확인합니다. 그다음 macOS 관리자 인증으로 아래 도니홈 전용 파일과 SMC 권한을 제거합니다. 인증을 취소해도 충전 복원 상태는 유지됩니다. 로그·목표 설정과 다른 battery 설치는 보존합니다.", action: "충전 복원 후 제거", destructive: true, paths: paths) {
            guard idle else { return }
            battery.uninstall()
        }
    }
    private func percentRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack { Text(title).font(Theme.font(14)); Spacer(); Stepper(value: value, in: range) { Text("\(value.wrappedValue)%").frame(width: 64) }.frame(width: 164) }
    }
    private func commandRow(_ title: String, on: BatteryCommand, off: BatteryCommand, enabled: Bool) -> some View {
        HStack {
            Text(title).font(Theme.font(14)); Spacer()
            Button("켜기") { battery.execute(on, title: "\(title) 켜기") }.buttonStyle(QuietButton()).disabled(!enabled)
            Button("끄기") { battery.execute(off, title: "\(title) 끄기") }.buttonStyle(QuietButton()).disabled(!enabled)
        }
    }
}
