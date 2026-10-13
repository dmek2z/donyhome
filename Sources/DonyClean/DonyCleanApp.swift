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
    @NSApplicationDelegateAdaptor(DonyAppDelegate.self) private var lifecycle
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("DonyClean · 도니클린", id: "main") {
            RootView(lifecycle: lifecycle).environmentObject(model).font(Theme.font(14)).preferredColorScheme(.light).frame(minWidth: 960, minHeight: 680)
        }.windowStyle(.hiddenTitleBar).defaultSize(width: 1130, height: 790).defaultPosition(.center)
            .commands {
                CommandGroup(replacing: .appSettings) { Button("도니클린 설정…") { model.preferencesShown = true }.keyboardShortcut(",") }
                CommandGroup(after: .newItem) { Button("통합 점검") { model.section = .overview; model.scanSmart() }.keyboardShortcut("r") }
            }
        MenuBarExtra {
            DonyMenuView().environmentObject(model)
        } label: {
            CodingCharacterLabel(animator: model.menuAnimator)
        }.menuBarExtraStyle(.window)
    }
}

@MainActor final class DonyAppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow?()
        return true
    }
}

struct RootView: View {
    let lifecycle: DonyAppDelegate
    @Environment(\.openWindow) private var openWindow
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
                    case .development: AIProjectsView()
                    case .applications: ApplicationsView()
                    case .history: HistoryView()
                    }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Theme.canvas)
        }.foregroundStyle(Theme.ink).tint(Theme.primary)
            .onAppear {
                lifecycle.openMainWindow = {
                    openWindow(id: "main")
                    if let window = NSApp.windows.first(where: { $0.title == "DonyClean · 도니클린" && $0.sheetParent == nil }) {
                        if window.isMiniaturized { window.deminiaturize(nil) }
                        window.makeKeyAndOrderFront(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .sheet(isPresented: Binding(get: { model.onboardingShown || model.preferencesShown }, set: { shown in if !shown { model.onboardingShown = false; model.preferencesShown = false } })) {
                if model.onboardingShown { OnboardingView().environmentObject(model).interactiveDismissDisabled() }
                else { PreferencesView().environmentObject(model) }
            }
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
                        if section == .development { Image(nsImage: CodingCharacter.developerAvatar).resizable().interpolation(.none).frame(width: 20, height: 20).accessibilityLabel("픽셀 개발자") } else { DonyIcon(section.icon).foregroundStyle(section.iconColor) }
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
                    Text("DonyClean " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0")).font(Theme.font(12)).foregroundStyle(Theme.secondary); Spacer()
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
            HStack {
                Text("도니클린").font(Theme.font(18, weight: .semibold))
                Spacer(); Button("종료") { NSApp.terminate(nil) }.buttonStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.secondary)
            }
            VStack(spacing: 12) {
                metric("CPU", value: DisplayFormat.percent(model.snapshot.cpuPercent))
                metric("메모리", value: model.snapshot.memoryUsed.map(DisplayFormat.bytes) ?? "—")
                HStack { Text("메모리 압박").foregroundStyle(Theme.secondary); Spacer(); Chip(text: model.snapshot.pressure.label, color: model.pressureColor) }.frame(height: 26)
                Divider()
                if let total = model.snapshot.diskTotal, let available = model.snapshot.diskAvailable, total > 0 {
                    metric("저장 공간", value: DisplayFormat.bytes(max(0, total - available)) + " / " + DisplayFormat.bytes(total))
                    ProgressView(value: min(1, max(0, Double(total - available) / Double(total)))).tint(Theme.primary)
                    HStack { Text("남은 용량").foregroundStyle(Theme.secondary); Spacer(); Text(DisplayFormat.bytes(available)).monospacedDigit() }.font(Theme.font(11))
                } else { metric("저장 공간", value: "—") }
            }.font(Theme.font(13)).frame(maxWidth: .infinity).panel(18)
            VStack(spacing: 12) {
                metric("배터리", value: model.snapshot.battery.map { String(format: "%.0f%%", $0.percent) + ($0.charging ? " · 충전" : $0.externalPower ? " · 전원 연결" : "") } ?? "미감지")
                metric("다운로드 ↓", value: model.snapshot.networkReceivedPerSecond.map { DisplayFormat.bytes(Int64($0)) + "/s" } ?? "—")
                metric("업로드 ↑", value: model.snapshot.networkSentPerSecond.map { DisplayFormat.bytes(Int64($0)) + "/s" } ?? "—")
            }.frame(maxWidth: .infinity).panel(18)
            Button {
                openWindow(id: "main")
                if let window = NSApp.windows.first(where: { $0.title == "DonyClean · 도니클린" && $0.sheetParent == nil }) {
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    window.makeKeyAndOrderFront(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
            } label: { Text("앱 열기").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
        }.padding(20).frame(width: 340).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
    }
    private func metric(_ title: String, value: String) -> some View {
        HStack { Text(title).font(Theme.font(13)).foregroundStyle(Theme.secondary); Spacer(minLength: 8); Text(value).font(Theme.font(13, weight: .medium)).monospacedDigit().lineLimit(1) }.frame(height: 26)
    }
}

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("설정").font(Theme.font(22, weight: .bold))
                Spacer(); Button("완료") { dismiss() }.buttonStyle(QuietButton())
            }.padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("과부하 알림", isOn: Binding(get: { model.notifyEnabled }, set: { model.setNotifications($0) })).toggleStyle(DonySwitch())
                        Text("CPU 85% · 메모리 압박 30초").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).panel(24)
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("로그인할 때 실행", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).toggleStyle(DonySwitch())
                        Button("로그인 항목 설정") { model.openLoginSettings() }.buttonStyle(QuietButton())
                    }.frame(maxWidth: .infinity, alignment: .leading).panel(24)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("메뉴 막대 캐릭터").font(Theme.font(17, weight: .semibold))
                        HStack(spacing: 12) {
                            Image(nsImage: model.menuAnimator.image).interpolation(.none).frame(width: 36, height: 28)
                            DonyChoices(options: ["컬러", "흑백"], selection: Binding(get: { model.characterMode.title }, set: { model.setCharacterMode($0 == "흑백" ? .monochrome : .color) }))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).panel(24)
                    AutomaticCleanupView()
                    Button("초기 설정 다시 열기") { model.preferencesShown = false; model.setupStep = 0; model.onboardingShown = true }.buttonStyle(QuietButton())
                    Button { model.section = .development; dismiss() } label: {
                        HStack { Text("개발 설정"); Spacer(); DonyIcon("chevron.right", size: 14) }.font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.body).padding(22).frame(maxWidth: .infinity).background(.white).clipShape(RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }.frame(width: 560, height: 620).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
    }
}
