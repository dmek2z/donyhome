#if DEBUG
import AppKit
import SwiftUI
import DonyCore

/// 화면 검토용 DEBUG 전용 픽스처. 임시 폴더의 가짜 항목만 쓰며 사용자 데이터·기록을 건드리지 않는다.
/// Info.plist의 DonyReviewFixture(상태 이름)가 있을 때만 동작하고 릴리스 빌드에는 포함되지 않는다.
@MainActor enum ReviewUIFixture {
    static func runIfRequested() -> Bool {
        guard let state = Bundle.main.object(forInfoDictionaryKey: "DonyReviewFixture") as? String,
              let path = Bundle.main.object(forInfoDictionaryKey: "DonyFixtureDirectory") as? String else { return false }
        let directory = URL(fileURLWithPath: path)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func make(_ name: String, kind: CandidateKind, bytes: Int, in folder: String) -> FileCandidate {
            let dir = directory.appendingPathComponent(folder)
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try! Data(repeating: 7, count: bytes).write(to: url)
            return try! FileCandidate.capture(url: url, root: dir, kind: kind)
        }
        let model = AppModel(store: HistoryStore(directory: directory.appendingPathComponent("actions")), automaticallySample: state == "overview")
        model.automaticStorageCheck = false; model.storageAlertsEnabled = false; model.notifyEnabled = false
        model.automaticCleanupEnabled = false; model.onboardingShown = false; model.resumedScanChecked = true
        model.permissionSetupReviewed = true; model.folder = directory
        model.excludedRecommendations = []
        model.introPage = state.hasPrefix("intro") ? Int(state.dropFirst("intro".count)) ?? 0 : nil
        if state.hasPrefix("intro") { model.onboardingShown = true }
        if state == "inspection" || state == "review" {
            let caches = ["com.google.Chrome", "com.spotify.client", "com.figma.Desktop"].enumerated().map { make($1, kind: .cache, bytes: 40_000 * ($0 + 1), in: "Caches") }
            let developer = [make("DerivedData-Build", kind: .developer, bytes: 90_000, in: "Developer")]
            var smart = SmartScanResult()
            smart.cleanup.items = caches; smart.developer.items = developer
            smart.decisions = Dictionary(uniqueKeysWithValues: caches.map { ($0.id, CleanupDecision(true, "14일 이상 변경 없는 확인된 앱 캐시")) })
            smart.developer.decisions = Dictionary(uniqueKeysWithValues: developer.map { ($0.id, CleanupDecision(true, "7일 이상 변경 없는 재생성 가능 캐시")) })
            model.smart = smart; model.smartDate = Date(); model.smartFolder = directory
            model.cleanup = smart.cleanup
            model.cleanupDecisions = Dictionary(uniqueKeysWithValues: caches.map { ($0.id, CleanupDecision(true, "14일 이상 변경 없는 확인된 앱 캐시")) })
            model.developer = smart.developer
            model.developer.decisions = Dictionary(uniqueKeysWithValues: developer.map { ($0.id, CleanupDecision(true, "7일 이상 변경 없는 재생성 가능 캐시")) })
            model.cleanupDate = Date(); model.developerDate = Date()
            if state == "review" { model.excludedRecommendations = [caches[1].id] }
            model.section = state == "review" ? .cleanup : .inspection
        } else if state.hasPrefix("onboarding") {
            model.onboardingShown = true; model.setupStep = Int(state.dropFirst("onboarding".count).prefix(1)) ?? 0
            model.connectedTools = [.codex, .claude, .terminal]
            model.connectedTools = [.codex, .claude]
            model.linkedProjects = ["my-app", "landing-page", "api-server"].map { LinkedProject(tool: .codex, path: directory.appendingPathComponent($0).path, enabled: $0 != "landing-page", discovered: true) }
                + ["dotfiles", "notes"].map { LinkedProject(tool: .claude, path: directory.appendingPathComponent($0).path, discovered: true) }
        } else if state == "development" {
            model.connectedTools = [.codex, .claude, .cursor, .hermes, .tmux, .terminal]
            model.section = .development; model.developmentMode = "도구 정리"
        } else if state == "clipboard" {
            func clip(_ text: String, app: String, minutes: Int, pinned: Bool = false) -> ClipboardItem {
                var item = ClipboardItem(representations: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]], application: app)
                item.firstCopiedAt = Date().addingTimeInterval(Double(-minutes * 60)); item.lastCopiedAt = item.firstCopiedAt; item.pinned = pinned
                if pinned { item.pinOrder = 1; item.pinLetter = "b" }
                return item
            }
            try? ClipboardStore(url: directory.appendingPathComponent("clipboard.json")).save([
                clip("https://github.com/dmek2z/donyhome", app: "Safari", minutes: 2),
                clip("git commit -m \"fix: 맥이 난로가 되기 전에 정리\"", app: "Terminal", minutes: 9),
                clip("npm run build && npm test", app: "Terminal", minutes: 21),
                clip("SELECT name, size FROM caches ORDER BY size DESC LIMIT 10;", app: "TablePlus", minutes: 48),
                clip("내일 오전 10시 · 도니홈 소개 정리", app: "Notes", minutes: 95),
                clip("hello@example.com", app: "Mail", minutes: 180, pinned: true)
            ])
            model.section = .clipboard
        } else if state == "dony" {
            model.section = .dony
        } else if state == "retention" {
            model.section = .development
        } else if state == "outcome" {
            let moved = make("old-cache.bin", kind: .cache, bytes: 120_000, in: "Caches")
            let trashed = ActionRecord(kind: "휴지통 이동", sourcePath: moved.id, trashPath: NSHomeDirectory() + "/.Trash/does-not-matter", bytes: 120_000, success: true, message: "")
            model.lastCleanupRecords = [trashed]
            model.lastCleanupOutcome = CleanupOutcome(movedBytes: 13_690_000_000, successful: 7, failed: 0, beforeAvailable: 275_000_000_000, afterAvailable: 275_000_000_000, permanent: false)
            model.section = .inspection
        }
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let lifecycle = DonyAppDelegate()
        let clipboard = ClipboardController(pasteboard: NSPasteboard(name: .init("donyhome-review-" + UUID().uuidString)), storeURL: directory.appendingPathComponent("clipboard.json"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1130, height: 900), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "도니홈 화면 검토 · 임시 데이터"; window.isReleasedWhenClosed = false
        if state == "character" { window.setContentSize(NSSize(width: 620, height: 330)) }
        window.contentView = state == "character"
            ? NSHostingView(rootView: VStack(spacing: 14) {
                Text("메뉴 막대 캐릭터").font(Theme.font(17, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                CharacterPreviewView(mode: .color)
                CharacterPreviewView(mode: .monochrome)
            }.padding(24).frame(width: 620, height: 330).background(Theme.canvas).preferredColorScheme(.light))
            : state == "retention"
            ? NSHostingView(rootView: RetentionSettingsSheet().environmentObject(model).font(Theme.font(14)).preferredColorScheme(.light))
            : NSHostingView(rootView: RootView(lifecycle: lifecycle).environmentObject(model).environmentObject(clipboard).font(Theme.font(14)).preferredColorScheme(.light))
        window.center(); window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        if let snapshot = Bundle.main.object(forInfoDictionaryKey: "DonyFixtureSnapshot") as? String {
            // 화면 녹화 권한 없이 창(시트 포함)의 내용을 PNG로 저장하고 종료한다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                if window.attachedSheet != nil, let base = window.contentView, let rep = base.bitmapImageRepForCachingDisplay(in: base.bounds) {
                    base.cacheDisplay(in: base.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snapshot + ".window.png"))
                }
                let view = (window.attachedSheet ?? window).contentView!
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snapshot))
                }
                NSApp.terminate(nil)
            }
        }
        app.run()
        return true
    }
}
#endif
