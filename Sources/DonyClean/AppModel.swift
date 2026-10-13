import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement
import DonyCore

enum Section: String, CaseIterable, Identifiable {
    case overview, cleanup, files, space, performance, applications, tools, history
    var id: String { rawValue }
    var title: String {
        switch self { case .overview: return "한눈에 보기"; case .cleanup: return "저장 공간 정리"; case .files: return "파일 정리"; case .space: return "용량 지도"; case .tools: return "유지보수"; case .performance: return "CPU · 메모리"; case .applications: return "앱 관리"; case .history: return "정리 기록" }
    }
    var iconColor: Color {
        switch self {
        case .overview, .history: return Color(hex: 0x8f959e)
        case .cleanup: return Color(hex: 0x25b79a)
        case .files, .space: return Color(hex: 0xf5a623)
        case .performance: return Color(hex: 0x4593fc)
        case .applications, .tools: return Color(hex: 0x8662ed)
        }
    }
    var icon: String {
        switch self { case .overview: return "house"; case .cleanup: return "sparkles"; case .files: return "folder"; case .space: return "externaldrive"; case .tools: return "gearshape"; case .performance: return "waveform.path.ecg"; case .applications: return "square.stack.3d.up"; case .history: return "clock.arrow.circlepath" }
    }
}

struct ScanActivity { let title: String; var count = 0; var detail = "준비 중" }
struct ReliefObservation { let app: String; let before: SystemSnapshot; let after: SystemSnapshot }

@MainActor final class AppModel: ObservableObject {
    @Published var cleanupMode = "캐시 · 로그"
    @Published var filesMode = "큰 파일"
    @Published var applicationsMode = "설치 앱"
    @Published var section: Section = .overview
    @Published var snapshot = SystemSnapshot()
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var activity: ScanActivity?
    @Published var operationBusy = false
    @Published var operationLabel = "작업 처리 중…"
    @Published var scanEpoch = UUID()
    @Published var cleanup = ScanResult()
    @Published var cleanupDecisions: [String: CleanupDecision] = [:]
    @Published var smart: SmartScanResult?
    @Published var smartDate: Date?
    @Published var smartFolder: URL?
    @Published var cleanupDate: Date?
    @Published var largeFiles = ScanResult()
    @Published var duplicates = DuplicateResult()
    @Published var filesDate: Date?
    @Published var duplicateDate: Date?
    @Published var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var similar = SimilarResult()
    @Published var similarDate: Date?
    @Published var developer = DeveloperResult()
    @Published var developerDate: Date?
    @Published var leftovers = LeftoverResult()
    @Published var leftoverDate: Date?
    @Published var clutter = ClutterResult()
    @Published var clutterDate: Date?
    @Published var spaceMap = SpaceResult()
    @Published var spaceRoot: URL?
    @Published var spaceDate: Date?
    @Published var localSnapshots: [String] = []
    @Published var snapshotsDate: Date?
    @Published var maintenanceOutput: String?
    @Published var applications = ApplicationResult()
    @Published var inventoryDate: Date?
    @Published var inspectedApp: InstalledApplication?
    @Published var appFiles = ScanResult()
    @Published var history: [ActionRecord] = []
    @Published var banner: String?
    @Published var lastRelief: ReliefObservation?
    @Published var notifyEnabled = UserDefaults.standard.bool(forKey: "overloadNotifications")
    @Published var preferencesShown = false

    private let sampler = SystemSampler()
    private let store = HistoryStore()
    private var historyWritable = true
    private var token: ScanToken?
    private var timer: Timer?
    private var sampling = false
    private var cpuHighSince: Date?
    private var memoryHighSince: Date?
    private var lastNotice = Date.distantPast
    private var lastSample = Date.distantPast
    var busy: Bool { activity != nil || operationBusy }
    var movedBytes: Int64 { history.filter { $0.success && $0.kind == "휴지통 이동" }.reduce(0) { $0 + $1.bytes } }
    var pressureColor: Color {
        switch snapshot.pressure { case .normal: return Theme.success; case .warning: return Theme.amber; case .critical: return Theme.red; case .unknown: return Theme.secondary }
    }

    init() {
        if let path = UserDefaults.standard.string(forKey: "scanFolder") {
            let saved = URL(fileURLWithPath: path)
            if FileSafety.allowedRoot(saved, kind: .large) { folder = saved }
        }
        do { history = try store.load() }
        catch { historyWritable = false; banner = "이전 기록을 읽지 못했습니다. 기존 파일은 보존합니다: " + error.localizedDescription }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if NSApp.windows.contains(where: { $0.isVisible && !$0.isMiniaturized }) || Date().timeIntervalSince(self.lastSample) >= 5 { self.sample() }
            }
        }
    }

    func sample() {
        guard !sampling else { return }; sampling = true
        let sampler = sampler
        Task {
            let value = await Task.detached(priority: .utility) { sampler.sample() }.value
            snapshot = value; sampling = false; lastSample = Date()
            if let cpu = value.cpuPercent { cpuHistory = Array((cpuHistory + [cpu]).suffix(60)) }
            if let memory = value.memoryPercent { memoryHistory = Array((memoryHistory + [memory]).suffix(60)) }
            checkOverload(value)
        }
    }

    private func checkOverload(_ value: SystemSnapshot) {
        let now = Date()
        if let cpu = value.cpuPercent, cpu >= 85 { if cpuHighSince == nil { cpuHighSince = now } } else { cpuHighSince = nil }
        if value.pressure == .warning || value.pressure == .critical { if memoryHighSince == nil { memoryHighSince = now } } else { memoryHighSince = nil }
        guard notifyEnabled, now.timeIntervalSince(lastNotice) >= 600 else { return }
        let cpuAlert = cpuHighSince.map { now.timeIntervalSince($0) >= 30 } ?? false
        let memoryAlert = memoryHighSince.map { now.timeIntervalSince($0) >= 30 } ?? false
        guard cpuAlert || memoryAlert else { return }
        lastNotice = now
        let content = UNMutableNotificationContent()
        content.title = "도니클린 · " + (memoryAlert ? "메모리가 바빠요" : "CPU가 바빠요")
        content.body = "과부하가 30초 이상 이어지고 있습니다. CPU · 메모리 화면에서 사용량 높은 앱을 확인해 주세요."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func setNotifications(_ enabled: Bool) {
        if !enabled { notifyEnabled = false; UserDefaults.standard.set(false, forKey: "overloadNotifications"); return }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                notifyEnabled = granted; UserDefaults.standard.set(granted, forKey: "overloadNotifications")
                if !granted { banner = "알림 권한이 꺼져 있습니다. 시스템 설정의 알림에서 도니클린을 허용해 주세요." }
            } catch { banner = "알림 설정을 적용하지 못했습니다: " + error.localizedDescription }
        }
    }

    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
            if SMAppService.mainApp.status == .requiresApproval { openLoginSettings(); banner = "로그인 항목 설정에서 도니클린 실행을 허용해 주세요." }
        } catch { banner = "로그인 실행 설정을 적용하지 못했습니다: " + error.localizedDescription }
    }

    func openLoginSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!) }
    func showFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "이 폴더 검사"; panel.message = "큰 파일과 중복 파일을 찾을 폴더를 선택하세요."; panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url {
            let resolved = url.resolvingSymlinksInPath()
            guard FileSafety.allowedRoot(resolved, kind: .large) else { banner = "시스템 폴더나 홈 전체 대신 다운로드·문서 같은 하위 폴더를 선택해 주세요."; return }
            UserDefaults.standard.set(resolved.path, forKey: "scanFolder")
            folder = resolved; similar = SimilarResult(); similarDate = nil; spaceRoot = resolved; spaceMap = SpaceResult(); spaceDate = nil; clutter = ClutterResult(); clutterDate = nil; smart = nil; smartDate = nil; largeFiles = ScanResult(); duplicates = DuplicateResult(); filesDate = nil; duplicateDate = nil; scanEpoch = UUID()
        }
    }

    func begin(_ title: String) -> (ScanToken, UUID)? {
        guard !busy else { return nil }
        let token = ScanToken(); self.token = token; activity = ScanActivity(title: title); scanEpoch = UUID()
        return (token, scanEpoch)
    }
    func progress(_ epoch: UUID) -> DonyCore.Scanner.Progress {
        { [weak self] count, detail in
            Task { @MainActor in
                guard let self, self.scanEpoch == epoch, self.activity != nil else { return }
                self.activity?.count = count; self.activity?.detail = detail
            }
        }
    }
    func finish(_ cancelled: Bool, issues: [ScanIssue]) {
        activity = nil; token = nil
        if cancelled { banner = "검사를 중단했습니다. 일부 결과가 표시될 수 있습니다." }
        else if !issues.isEmpty { banner = "\(issues.count)개 항목을 확인하지 못했습니다. 검사 결과의 건너뛴 항목을 확인해 주세요." }
        sample()
    }
    func cancel() { token?.cancel(); activity?.detail = "중단하는 중…" }

    var similarOriginals: [FileCandidate] { similar.groups.map(\.original) }
    var recommendedCleanup: [FileCandidate] {
        RecommendedActions.plan(cleanup: cleanup.items.filter { cleanupDecisions[$0.id]?.isRecommended == true }, duplicates: duplicates.groups, includeCopies: false, preserving: similarOriginals).items
    }
    var recommendedDeveloper: [FileCandidate] {
        RecommendedActions.plan(cleanup: developer.recommended, duplicates: duplicates.groups, includeCopies: false, preserving: similarOriginals).items
    }
    var recommendedDuplicateCopies: [FileCandidate] {
        RecommendedActions.plan(cleanup: [], duplicates: duplicates.groups, preserving: similarOriginals).items
    }
    var duplicateCopies: [FileCandidate] { duplicates.groups.flatMap(\.copies) }
    var duplicateOriginals: [String: FileCandidate] {
        Dictionary(uniqueKeysWithValues: duplicates.groups.flatMap { group in group.copies.map { ($0.id, group.original) } })
    }
    var runningBundleIDs: Set<String> { Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier)) }
    func scanSmart() {
        guard let (token, epoch) = begin("스마트 점검") else { return }
        smart = nil; smartDate = nil
        let folder = folder; let running = runningBundleIDs; let report = progress(epoch)
        Task {
            let result = await Task.detached(priority: .utility) { SmartScanner.scan(folder: folder, runningBundleIDs: running, token: token, progress: report) }.value
            smart = result; smartDate = Date(); smartFolder = folder
            cleanup = result.cleanup; cleanupDecisions = result.decisions; cleanupDate = smartDate
            largeFiles = result.largeFiles; filesDate = smartDate; duplicates = result.duplicates; duplicateDate = smartDate
            applications = result.applications; inventoryDate = smartDate
            developer = result.developer; developerDate = smartDate
            leftovers = result.leftovers; leftoverDate = smartDate
            clutter = result.clutter; clutterDate = smartDate
            spaceMap = result.space; spaceRoot = folder; spaceDate = smartDate
            similar = result.similar; similarDate = smartDate
            finish(result.cancelled, issues: result.issues)
        }
    }
    func recommendedPlan(includeCleanup: Bool, includeDuplicates: Bool, includeDeveloper: Bool = true) -> RecommendedPlan {
        RecommendedActions.plan(cleanup: (includeCleanup ? recommendedCleanup : []) + (includeDeveloper ? recommendedDeveloper : []), duplicates: duplicates.groups, includeCopies: includeDuplicates, preserving: similarOriginals)
    }
    func runRecommended(includeCleanup: Bool, includeDuplicates: Bool, includeDeveloper: Bool = true) {
        guard let smart, !smart.cancelled else { return }
        let plan = recommendedPlan(includeCleanup: includeCleanup, includeDuplicates: includeDuplicates, includeDeveloper: includeDeveloper)
        moveToTrash(plan.items, originals: plan.originals, recommendedOnly: true)
    }
    func scanCleanup() {
        guard let (token, epoch) = begin("캐시 · 로그 검사") else { return }
        smart = nil; smartDate = nil; cleanupDecisions = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [(URL, CandidateKind)] = [(home.appendingPathComponent("Library/Caches"), .cache), (home.appendingPathComponent("Library/Logs"), .log)]
        let exclusions = runningBundleIDs
        let report = progress(epoch)
        Task {
            let result = await Task.detached(priority: .utility) {
                var result = Scanner.cleanup(roots: roots, excluding: exclusions, token: token, progress: report)
                var decisions: [String: CleanupDecision] = [:]
                for item in result.items {
                    if token.isCancelled { result.cancelled = true; break }
                    do { decisions[item.id] = try CleanupPolicy().reason(for: item, runningBundleIDs: exclusions, token: token) }
                    catch { if !token.isCancelled { result.issues.append(ScanIssue(path: item.id, message: error.localizedDescription)) } }
                }
                return (result, decisions)
            }.value
            cleanup = result.0; cleanupDecisions = result.1
            cleanupDate = Date(); finish(cleanup.cancelled, issues: cleanup.issues)
        }
    }
    func scanFiles(duplicatesOnly: Bool) {
        guard let (token, epoch) = begin(duplicatesOnly ? "중복 파일 검사" : "큰 파일 검사") else { return }
        smart = nil; smartDate = nil
        let root = folder; let report = progress(epoch)
        Task {
            if duplicatesOnly {
                duplicates = await Task.detached(priority: .utility) { DuplicateFinder.find(root: root, token: token, progress: report) }.value
                duplicateDate = Date(); finish(duplicates.cancelled, issues: duplicates.issues)
            } else {
                largeFiles = await Task.detached(priority: .utility) { Scanner.largeFiles(root: root, token: token, progress: report) }.value
                filesDate = Date(); finish(largeFiles.cancelled, issues: largeFiles.issues)
            }
        }
    }
    func scanApplications() {
        guard let (token, _) = begin("설치된 앱 확인") else { return }
        Task {
            applications = await Task.detached(priority: .utility) { ApplicationScanner.inventory(token: token) }.value
            inventoryDate = Date(); inspectedApp = nil; appFiles = ScanResult(); finish(applications.cancelled, issues: applications.issues)
        }
    }
    func inspect(_ app: InstalledApplication) {
        guard let (token, _) = begin(app.name + " · 관련 파일 확인") else { return }
        inspectedApp = app; appFiles = ScanResult()
        Task {
            appFiles = await Task.detached(priority: .utility) { ApplicationScanner.inspect(app, token: token) }.value
            finish(appFiles.cancelled, issues: appFiles.issues)
        }
    }

    func canQuit(_ process: ProcessReading) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: process.pid), !app.isTerminated else { return false }
        return ProcessPolicy.canQuit(process, currentUID: getuid(), ownPID: getpid(), regularApplication: app.activationPolicy == .regular) && app.bundleIdentifier != Bundle.main.bundleIdentifier
    }
    func quit(_ process: ProcessReading, force: Bool = false) {
        guard !operationBusy, canQuit(process), let app = NSRunningApplication(processIdentifier: process.pid) else { return }
        let title = force ? process.name + " 강제 종료" : process.name + " 종료"
        let body = force ? "저장하지 않은 작업이 사라질 수 있습니다. 이 앱을 강제로 종료할까요?" : "이 앱에 일반 종료를 요청합니다. 작업을 저장한 후 진행하세요. 저장 대화상자가 뜨면 앱에서 처리해 주세요."
        guard confirm(title, message: body, action: force ? "강제 종료" : "종료 요청", destructive: force) else { return }
        do { try ProcessPolicy.verifyIdentity(process) }
        catch { banner = error.localizedDescription; return }
        guard canQuit(process) else { banner = DonyError.protectedProcess.localizedDescription; return }
        let before = snapshot
        let accepted = force ? app.forceTerminate() : app.terminate()
        let historyError = append([ActionRecord(kind: force ? "앱 강제 종료 요청" : "앱 종료 요청", sourcePath: process.path, trashPath: nil, bytes: 0, success: accepted, message: accepted ? "종료 요청을 전달했습니다. 실제 종료와 변화는 시스템 수치에서 확인하세요." : "앱이 종료 요청을 받아들이지 않았습니다.")])
        banner = OperationFeedback.compose(summary: accepted ? process.name + "에 종료를 요청했습니다." : "종료 요청이 처리되지 않았습니다.", historyError: historyError)
        Task {
            try? await Task.sleep(for: .seconds(3))
            let sampler = sampler
            let after = await Task.detached(priority: .utility) { sampler.sample() }.value
            snapshot = after; lastRelief = ReliefObservation(app: process.name, before: before, after: after)
        }
    }

    func quitSelected(_ processes: [ProcessReading]) {
        guard !busy, !processes.isEmpty else { return }
        let eligible = processes.filter { canQuit($0) }
        guard !eligible.isEmpty else { banner = "종료 가능한 앱이 없습니다."; return }
        guard confirm("선택한 앱 \(eligible.count)개 종료", message: "사용하지 않는 앱인지 확인하고 작업을 저장해 주세요. 일반 종료를 요청하며 저장 창이 뜨면 해당 앱에서 처리해 주세요.", action: "종료 요청", destructive: true, paths: eligible.map { $0.name + " · PID \($0.pid)" }) else { return }
        let before = snapshot
        var records: [ActionRecord] = []
        for process in eligible {
            do {
                try ProcessPolicy.verifyIdentity(process)
                guard canQuit(process), let app = NSRunningApplication(processIdentifier: process.pid) else { throw DonyError.protectedProcess }
                let accepted = app.terminate()
                records.append(ActionRecord(kind: "앱 종료 요청", sourcePath: process.path, trashPath: nil, bytes: 0, success: accepted, message: accepted ? "일반 종료를 요청했습니다." : "앱이 종료 요청을 받아들이지 않았습니다."))
            } catch { records.append(ActionRecord(kind: "앱 종료 요청", sourcePath: process.path, trashPath: nil, bytes: 0, success: false, message: error.localizedDescription)) }
        }
        let warning = append(records)
        banner = OperationFeedback.compose(summary: "\(records.filter(\.success).count)개 앱에 종료를 요청했습니다. 실제 종료와 사용량 변화는 시스템 수치에서 확인하세요.", historyError: warning)
        Task {
            try? await Task.sleep(for: .seconds(3))
            let sampler = sampler
            let after = await Task.detached(priority: .utility) { sampler.sample() }.value
            snapshot = after; lastRelief = ReliefObservation(app: "선택한 앱", before: before, after: after)
        }
    }

    func moveToTrash(_ candidates: [FileCandidate], originals: [String: FileCandidate] = [:], ownerBundleID: String? = nil, recommendedOnly: Bool = false) {
        guard !busy, !candidates.isEmpty else { return }
        let body = "선택한 \(candidates.count)개 항목 · \(DisplayFormat.bytes(candidates.reduce(0) { $0 + $1.bytes }))\n휴지통을 비우기 전에는 저장 공간이 즉시 늘어나지 않습니다." + (candidates.contains { $0.kind == .support } ? "\n관련 파일에는 설정과 사용자 데이터가 포함될 수 있습니다." : "")
        guard confirm("선택한 항목을 휴지통으로 이동", message: body, action: "휴지통으로 이동", destructive: true, paths: candidates.map { $0.url.path }) else { return }
        operationLabel = "선택한 항목을 다시 확인하고 이동하는 중…"
        operationBusy = true
        let operationToken = ScanToken()
        Task {
            var results: [ActionRecord] = []
            for candidate in candidates {
                let running = NSWorkspace.shared.runningApplications
                let ownerRunning = ownerBundleID.map { id in running.contains { $0.bundleIdentifier == id && !$0.isTerminated } } ?? false
                let bundleIDs = Set(running.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
                let policy = CleanupPolicy()
                let original = originals[candidate.id]
                let tools = RunningTools.read().union(bundleIDs)
                let developerRunning = DeveloperCleanup.activeOwner(of: candidate.url, runningTools: tools) || original.map { DeveloperCleanup.activeOwner(of: $0.url, runningTools: tools) } == true
                let cacheRunning = policy.runningOwner(of: candidate.url, runningBundleIDs: bundleIDs) != nil || original.map { policy.runningOwner(of: $0.url, runningBundleIDs: bundleIDs) != nil } == true
                if ownerRunning || cacheRunning || developerRunning {
                    results.append(ActionRecord(kind: "휴지통 이동", sourcePath: candidate.url.path, trashPath: nil, bytes: 0, success: false, message: "관련 앱을 종료한 뒤 다시 시도해 주세요.")); continue
                }
                let orphan = ownerBundleID == nil ? leftovers.items.first(where: { $0.id == candidate.id }) : nil
                let result = await Task.detached(priority: .utility) {
                    do {
                        if candidate.kind == .space { try SpaceMap.validateSelection(candidate) }
                        if candidate.kind == .developer { try DeveloperCleanup.validate(candidate, runningTools: tools, requireOld: recommendedOnly) }
                        if let orphan {
                            let installed = Set(ApplicationScanner.inventory(token: operationToken).apps.map(\.bundleID))
                            try LeftoverScanner.validate(orphan, installedIDs: installed, runningIDs: bundleIDs)
                        }
                    } catch { return ActionRecord(kind: "휴지통 이동", sourcePath: candidate.id, trashPath: nil, bytes: 0, success: false, message: error.localizedDescription) }
                    if recommendedOnly && (candidate.kind == .cache || candidate.kind == .log) {
                        do {
                            guard try CleanupPolicy().reason(for: candidate, runningBundleIDs: bundleIDs, token: operationToken).isRecommended else { throw DonyError.changed }
                        } catch { return ActionRecord(kind: "휴지통 이동", sourcePath: candidate.id, trashPath: nil, bytes: 0, success: false, message: "추천 기준을 다시 통과하지 못했습니다: " + error.localizedDescription) }
                    }
                    return TrashService.move(candidate, keeping: original, token: operationToken)
                }.value
                results.append(result)
            }
            let moved = Set(results.filter(\.success).map(\.sourcePath))
            cleanup.items.removeAll { moved.contains($0.id) }; largeFiles.items.removeAll { moved.contains($0.id) }; appFiles.items.removeAll { moved.contains($0.id) }
            developer.items.removeAll { moved.contains($0.id) }; leftovers.items.removeAll { moved.contains($0.id) }
            clutter.oldFiles.items.removeAll { moved.contains($0.id) }; clutter.installers.items.removeAll { moved.contains($0.id) }
            if !moved.isEmpty { spaceMap = SpaceResult(); spaceDate = nil }
            duplicates.groups = duplicates.groups.compactMap { group in
                let copies = group.copies.filter { !moved.contains($0.id) }
                return copies.isEmpty ? nil : DuplicateGroup(original: group.original, copies: copies)
            }
            similar.groups = similar.groups.compactMap { group in
                let copies = group.copies.filter { !moved.contains($0.candidate.id) }
                return copies.isEmpty ? nil : SimilarGroup(original: group.original, copies: copies)
            }
            if let inspectedApp, moved.contains(inspectedApp.url.path) { applications.apps.removeAll { $0.id == inspectedApp.id } }
            if smart != nil { smart?.cleanup = cleanup; smart?.duplicates = duplicates; smart?.largeFiles = largeFiles; smart?.developer = developer; smart?.leftovers = leftovers; smart?.clutter = clutter; smart?.space = spaceMap; smart?.similar = similar }
            let historyError = append(results); operationBusy = false; scanEpoch = UUID(); sample()
            let failures = results.filter { !$0.success }.count
            banner = OperationFeedback.compose(summary: "\(moved.count)개 항목을 휴지통으로 이동했습니다." + (failures > 0 ? " \(failures)개는 이동하지 못했습니다. 정리 기록에서 이유를 확인하세요." : ""), historyError: historyError)
        }
    }
    func append(_ records: [ActionRecord]) -> String? {
        history = Array((Array(records.reversed()) + history).prefix(500))
        guard historyWritable else { return "기존 기록 파일에 문제가 있어 이번 기록은 앱 안에서만 유지합니다." }
        do { try store.save(history); return nil } catch { return "기록을 저장하지 못했습니다: " + error.localizedDescription }
    }
    func confirm(_ title: String, message: String, action: String, destructive: Bool, paths: [String] = []) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.alertStyle = destructive ? .warning : .informational
        alert.addButton(withTitle: action); alert.addButton(withTitle: "취소")
        // Return defaults to cancellation for destructive confirmations.
        if destructive { alert.buttons[0].keyEquivalent = ""; alert.buttons[1].keyEquivalent = "\r" }
        if !paths.isEmpty {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 430, height: 160)); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.isSelectable = true; text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.string = paths.joined(separator: "\n\n"); text.textContainerInset = NSSize(width: 8, height: 8); scroll.documentView = text; alert.accessoryView = scroll
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
