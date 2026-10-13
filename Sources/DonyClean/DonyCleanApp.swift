import SwiftUI
import AppKit
import DonyCore

@main enum DonyEntry {
    static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            let sampler = SystemSampler(); _ = sampler.sample(); Thread.sleep(forTimeInterval: 1)
            let snapshot = sampler.sample(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot), let json = String(data: data, encoding: .utf8) { print(json) }
            return
        }
        if CommandLine.arguments.contains("--snapshots") {
            do { for date in try Maintenance.listSnapshots() { print(date) } }
            catch { print("ERROR: " + error.localizedDescription) }
            return
        }
        if CommandLine.arguments.contains("--smart-plan") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            var folder = home.appendingPathComponent("Downloads")
            if let index = CommandLine.arguments.firstIndex(of: "--folder"), CommandLine.arguments.count > index + 1 { folder = URL(fileURLWithPath: CommandLine.arguments[index + 1]) }
            let running = Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
            let result = SmartScanner.scan(folder: folder, runningBundleIDs: running, token: ScanToken())
            let plan = RecommendedActions.plan(cleanup: result.recommended + result.developer.recommended, duplicates: result.duplicates.groups, preserving: result.similar.groups.map(\.original))
            let output: [String: Any] = [
                "readOnly": true, "cancelled": result.cancelled, "folder": folder.path,
                "developerFound": result.developer.items.count, "developerRecommended": result.developer.recommended.count,
                "trashItems": result.trash.items.count, "trashBytes": result.trash.totalBytes, "similarGroups": result.similar.groups.count, "leftoverCandidates": result.leftovers.items.count, "oldFiles": result.clutter.oldFiles.items.count, "installers": result.clutter.installers.items.count, "mappedBytes": result.space.totalBytes,
                "cleanupFound": result.cleanup.items.count, "cleanupRecommended": result.recommended.count,
                "duplicateGroups": result.duplicates.groups.count, "duplicateCopies": result.duplicates.groups.flatMap(\.copies).count,
                "largeFiles": result.largeFiles.items.count, "applications": result.applications.apps.count,
                "issues": result.issues.count, "recommendedBytes": plan.bytes,
                "recommended": plan.items.map { ["path": $0.id, "kind": $0.kind.rawValue, "bytes": $0.bytes] as [String: Any] }
            ]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--scan"), CommandLine.arguments.count > index + 1 {
            let root = URL(fileURLWithPath: CommandLine.arguments[index + 1]); let result = Scanner.largeFiles(root: root, token: ScanToken())
            print("\(result.visited) items checked; \(result.items.count) large files; \(result.issues.count) skipped")
            for file in result.items { print(DisplayFormat.bytes(file.bytes) + "\t" + file.url.path) }
            for issue in result.issues { print("SKIPPED\t" + issue.path + "\t" + issue.message) }
            return
        }
        Theme.registerFonts()
        DonyCleanApp.main()
    }
}

struct DonyCleanApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("DonyClean · 도니클린", id: "main") {
            RootView().environmentObject(model).font(Theme.font(14)).preferredColorScheme(.light).frame(minWidth: 960, minHeight: 680)
        }.windowStyle(.hiddenTitleBar).defaultSize(width: 1130, height: 790).defaultPosition(.center)
            .commands {
                CommandGroup(replacing: .appSettings) { Button("도니클린 설정…") { model.preferencesShown = true }.keyboardShortcut(",") }
                CommandGroup(after: .newItem) { Button("통합 점검") { model.section = .overview; model.scanSmart() }.keyboardShortcut("r") }
            }
        MenuBarExtra {
            DonyMenuView().environmentObject(model)
        } label: {
            DonyLabel("DC " + DisplayFormat.percent(model.snapshot.cpuPercent), icon: "sparkles")
        }.menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let banner = model.banner {
                        HStack(spacing: 10) {
                            DonyIcon("info.circle").foregroundStyle(Theme.secondary)
                            Text(banner).font(Theme.font(12)).fixedSize(horizontal: false, vertical: true)
                            Spacer(); Button { model.banner = nil } label: { DonyIcon("xmark", size: 14) }.buttonStyle(.plain)
                        }.panel(14)
                    }
                    ScanProgressView()
                    switch model.section {
                    case .overview: OverviewView()
                    case .cleanup: CleanupView()
                    case .files: FilesView()
                    case .space: SpaceView()
                    case .tools: ToolsView()
                    case .performance: PerformanceView()
                    case .applications: ApplicationsView()
                    case .history: HistoryView()
                    }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Theme.canvas)
        }.foregroundStyle(Theme.ink).tint(Theme.primary)
            .sheet(isPresented: $model.preferencesShown) { PreferencesView().environmentObject(model) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                DonyLogo(size: 36)
                Text("도니클린").font(Theme.font(19, weight: .bold)).foregroundStyle(Theme.body)
            }.padding(.horizontal, 12).padding(.top, 43).padding(.bottom, 26)
            HStack(spacing: 10) {
                DonyIcon("laptopcomputer").font(Theme.font(18)).foregroundStyle(Theme.secondary)
                Text("Dony의 Mac").font(Theme.font(14, weight: .medium))
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xe8ebef).opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.bottom, 24)
            ForEach(Section.allCases) { section in
                Button { model.section = section } label: {
                    HStack(spacing: 12) {
                        DonyIcon(section.icon).foregroundStyle(section.iconColor)
                        Text(section.title).font(Theme.font(14, weight: model.section == section ? .semibold : .medium))
                        Spacer()
                    }.foregroundStyle(Theme.body)
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(model.section == section ? Color(hex: 0xe8ebef) : .clear).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).padding(.bottom, 4)
            }
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 12) {
                Rectangle().fill(Theme.line).frame(height: 1)
                HStack {
                    Text("DonyClean 1.0").font(Theme.font(12)).foregroundStyle(Theme.secondary); Spacer()
                    Button { model.preferencesShown = true } label: { DonyIcon("gearshape").foregroundStyle(Theme.secondary) }.buttonStyle(.plain).help("도니클린 설정")
                }
            }.padding(.horizontal, 10).padding(.bottom, 25)
        }.padding(.horizontal, 18).frame(width: 240).frame(maxHeight: .infinity).background(Theme.sidebar).overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }
}

struct DonyMenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("donyclean").font(Theme.font(18, weight: .bold)); Spacer(); DonyIcon("sparkles").foregroundStyle(Theme.primary) }
            HStack { Text("CPU"); Spacer(); Text(DisplayFormat.percent(model.snapshot.cpuPercent)).monospacedDigit() }
            HStack { Text("메모리"); Spacer(); Text(model.snapshot.memoryUsed.map(DisplayFormat.bytes) ?? "—").monospacedDigit() }
            HStack { Text("메모리 압박"); Spacer(); Chip(text: model.snapshot.pressure.label, color: model.pressureColor) }
            if let battery = model.snapshot.battery { HStack { Text("배터리"); Spacer(); Text(String(format: "%.0f%%", battery.percent) + (battery.charging ? " · 충전" : "")).monospacedDigit() } }
            HStack { Text("네트워크 ↓"); Spacer(); Text(model.snapshot.networkReceivedPerSecond.map { DisplayFormat.bytes(Int64($0)) + "/s" } ?? "—").monospacedDigit() }
            Divider()
            Text("사용량 높은 앱을 확인하고 선택해서 종료하세요.").font(Theme.font(11)).foregroundStyle(Theme.secondary)
            Button { model.section = .performance; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } label: { Text("CPU · 메모리 관리 열기").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
            HStack {
                Button("도니클린 열기") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }.buttonStyle(.plain)
                Spacer(); Button("완전히 종료") { NSApp.terminate(nil) }.buttonStyle(.plain)
            }.font(Theme.font(11)).foregroundStyle(Theme.secondary)
        }.font(Theme.font(13)).padding(22).frame(width: 300).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
    }
}

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("도니클린 설정").font(Theme.font(22, weight: .bold)); Spacer(); Button("완료") { dismiss() }.buttonStyle(QuietButton()) }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("지속적인 CPU · 메모리 과부하 알림", isOn: Binding(get: { model.notifyEnabled }, set: { model.setNotifications($0) }))
                Text("CPU 85% 이상 또는 메모리 압박이 30초간 이어지면 알려줘요. 같은 알림은 10분에 한 번만 표시합니다.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
            }.panel()
            VStack(alignment: .leading, spacing: 12) {
                Toggle("로그인할 때 도니클린 실행", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                Button("로그인 항목 · 백그라운드 앱 설정 열기") { model.openLoginSettings() }.buttonStyle(QuietButton())
            }.panel()
            Text("모든 검사와 기록은 이 Mac에만 저장됩니다. 창을 닫아도 메뉴 막대에서 상태를 확인할 수 있어요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
        }.padding(28).frame(width: 540).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
    }
}
