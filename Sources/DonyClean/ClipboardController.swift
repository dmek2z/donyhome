import AppKit
import SwiftUI
import Carbon
import Vision
import DonyCore

@MainActor final class ClipboardController: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var preferences: ClipboardPreferences { didSet { savePreferences(); if oldValue.hotkeyEnabled != preferences.hotkeyEnabled || oldValue.hotkeyKeyCode != preferences.hotkeyKeyCode || oldValue.hotkeyModifiers != preferences.hotkeyModifiers { registerHotkey() } } }
    @Published var query = ""
    @Published var status = ""
    @Published var ignoreNextCopy = false
    @Published private(set) var pasteStack: [UUID] = []
    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let defaults: UserDefaults
    private let captureSession: ClipboardCaptureSession
    private var timer: Timer?
    private var storeWritable = true
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var panel: NSPanel?
    private var sourceApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var pendingPaste: Task<Void, Never>?
    private var stackMonitor: Any?
    private var stackActive = false
    private var stackPlain = false
    private var stackPreparedCount: Int?
    private var queueState = ClipboardPasteQueue()
    private var stackRequiresExplicitNext = false
    private var suppressStackUntil = Date.distantPast
    var visibleItems: [ClipboardItem] { ClipboardHistory.search(ClipboardHistory.sorted(items, by: preferences.sort, pinsAtBottom: preferences.pinsAtBottom), query: query, mode: preferences.search) }
    var accessibilityAllowed: Bool { AXIsProcessTrusted() }
    var needsRecovery: Bool { !storeWritable }
    init(pasteboard: NSPasteboard = .general, storeURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.pasteboard = pasteboard; self.defaults = defaults
        captureSession = ClipboardCaptureSession(pasteboard: pasteboard, application: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("donyhome/Clipboard", isDirectory: true)
        store = ClipboardStore(url: storeURL ?? directory.appendingPathComponent("history.json"))
        preferences = defaults.data(forKey: "clipboard.preferences").flatMap { try? JSONDecoder().decode(ClipboardPreferences.self, from: $0) } ?? ClipboardPreferences()
        preferences.hotkeyKeyCode = defaults.object(forKey: "clipboard.preferences") == nil ? 8 : preferences.hotkeyKeyCode // command shift C
        do { items = try store.load() } catch { storeWritable = false; status = "기록 파일을 읽을 수 없어요. 원본을 보존했어요. 기록을 초기화하면 다시 저장해요." }
    }
    func start() {
        guard timer == nil else { return }
        rememberSource(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self else { return }
                var capturePreferences = self.preferences
                if self.ignoreNextCopy, self.captureSession.hasPendingChange { capturePreferences.paused = true; self.ignoreNextCopy = false }
                if let item = self.captureSession.applicationDidActivate(app?.bundleIdentifier, preferences: capturePreferences) { self.accept(item) }
                self.rememberSource(app)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        registerHotkey()
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }; activationObserver = nil
        if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
        pendingPaste?.cancel(); if let stackMonitor { NSEvent.removeMonitor(stackMonitor) }; stackMonitor = nil; panel?.close()
    }
    private func rememberSource(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        sourceApp = app
    }
    func poll() {
        guard captureSession.hasPendingChange else { return }
        if ignoreNextCopy { ignoreNextCopy = false; captureSession.synchronize(); return }
        guard let item = captureSession.poll(preferences: preferences) else { return }
        accept(item)
    }
    private func accept(_ item: ClipboardItem) {
        clearStack()
        items = ClipboardHistory.adding(item, to: items, limit: preferences.limit); persist(); recognizeImage(item)
    }
    func setPinned(_ item: ClipboardItem) { guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }; items[index].pinned.toggle()
        if items[index].pinned {
            items[index].pinOrder = (items.compactMap(\.pinOrder).max() ?? 0) + 1
            items[index].pinLetter = availablePinLetters.first
        } else { items[index].pinLetter = nil }
        persist() }
    var availablePinLetters: [String] { "bcdefghijklmnotuxy".map(String.init).filter { letter in !items.contains { $0.pinned && $0.pinLetter == letter } } }
    func assignPinLetter(_ item: ClipboardItem, letter: String) {
        guard availablePinLetters.contains(letter), let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinLetter = letter; persist()
    }
    func movePin(_ item: ClipboardItem, up: Bool) {
        let pins = visibleItems.filter(\.pinned)
        guard let position = pins.firstIndex(where: { $0.id == item.id }) else { return }
        let other = position + (up ? -1 : 1)
        guard pins.indices.contains(other), let first = items.firstIndex(where: { $0.id == item.id }), let second = items.firstIndex(where: { $0.id == pins[other].id }) else { return }
        let order = items[first].pinOrder; items[first].pinOrder = items[second].pinOrder; items[second].pinOrder = order; persist()
    }
    private func recognizeImage(_ item: ClipboardItem) {
        guard let data = item.imageData else { return }
        let id = items.first(where: { $0.representations == item.representations })?.id ?? item.id
        Task.detached(priority: .utility) { [weak self] in
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(data: data).perform([request])
                let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                await MainActor.run { [weak self] in
                    guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                    self.items[index].recognizedText = text; self.persist()
                }
            } catch { /* Original image bytes remain usable when recognition fails. */ }
        }
    }
    func delete(_ item: ClipboardItem) { items.removeAll { $0.id == item.id }; pasteStack.removeAll { $0 == item.id }; persist() }
    func clear(includePinned: Bool = false) { items.removeAll { includePinned || !$0.pinned }; pasteStack = []; persist() }
    func resetUnreadableStore() {
        do {
            if FileManager.default.fileExists(atPath: store.url.path) {
                let backup = store.url.deletingLastPathComponent().appendingPathComponent("unreadable-\(UUID().uuidString).json")
                try FileManager.default.moveItem(at: store.url, to: backup)
            }
            storeWritable = true; status = ""; persist()
        } catch { status = "원본 기록을 보존할 수 없어 초기화를 중단했어요: \(error.localizedDescription)" }
    }
    func edit(_ item: ClipboardItem, text: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].representations = [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]]; persist()
    }
    @discardableResult func copy(_ item: ClipboardItem, plainText: Bool = false) -> Bool {
        guard ClipboardCapture.write(item, to: pasteboard, plainText: plainText) else { status = "클립보드에 복사하지 못했어요."; return false }
        captureSession.synchronize()
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].lastCopiedAt = Date(); items[index].numberOfCopies += 1; persist() }
        status = plainText ? "일반 텍스트로 복사했어요." : "복사했어요."
        if let app = sourceApp, app.bundleURL?.lastPathComponent == "Chrome Remote Desktop.app" || app.localizedName?.contains("NetBeans") == true {
            NSApp.activate(ignoringOtherApps: true); NSApp.hide(nil)
        }
        return true
    }
    func requestAccessibility() { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    func paste(_ item: ClipboardItem, plainText: Bool = false) {
        guard copy(item, plainText: plainText) else { return }
        guard accessibilityAllowed else { status = "복사했어요. 붙여넣기는 설정에서 손쉬운 사용 권한을 허용한 후 사용할 수 있어요."; return }
        guard let target = sourceApp, !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { status = "복사했어요. 붙여넣을 앱으로 돌아가 주세요."; return }
        let ticket = ClipboardPasteTicket(changeCount: pasteboard.changeCount, targetProcessIdentifier: target.processIdentifier)
        if stackActive, pasteStack.first == item.id { queueState.prepare(ticket: ticket); stackPreparedCount = ticket.changeCount }
        panel?.orderOut(nil)
        pendingPaste?.cancel()
        target.activate(options: [.activateIgnoringOtherApps])
        pendingPaste = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            guard !target.isTerminated, ticket.isValid(pasteboard: self.pasteboard, frontmostProcessIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier) else { self.status = "대상 앱 또는 클립보드가 바뀌어 자동 붙여넣기를 중단했어요."; return }
            let source = CGEventSource(stateID: .combinedSessionState)
            // macOS virtual key 9 = V. Modifier-side flag follows Maccy/Clipy's workaround.
            let down = CGEvent(keyboardEventSource: source, virtualKey: ClipboardKeyboardLayout.pasteKeyCode, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: ClipboardKeyboardLayout.pasteKeyCode, keyDown: false)
            down?.flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008); up?.flags = down?.flags ?? .maskCommand
            guard let down, let up else { self.status = "붙여넣기 키 입력을 만들지 못했어요."; return }
            self.suppressStackUntil = Date().addingTimeInterval(0.5)
            down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)
            if self.stackActive, self.pasteStack.first == item.id { self.stackRequiresExplicitNext = true; self.advanceStack() }
        }
    }
    func toggleStack(_ item: ClipboardItem) { if pasteStack.contains(item.id) { pasteStack.removeAll { $0 == item.id } } else { pasteStack.append(item.id) } }
    func clearStack() { pasteStack = []; stackActive = false; stackPreparedCount = nil; queueState = ClipboardPasteQueue() }
    func selectStack(_ selected: [ClipboardItem]) { pasteStack = selected.map(\.id); stackActive = false }
    func reverseStack() { pasteStack.reverse(); if stackActive { prepareStackItem() } }
    func copyStackAsText() {
        let text = pasteStack.compactMap { id in items.first { $0.id == id }?.text }.joined(separator: "\n")
        guard !text.isEmpty else { status = "합칠 텍스트가 없어요."; return }
        _ = copy(ClipboardItem(representations: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]]))
        clearStack()
    }
    func startStack(plainText: Bool = false) {
        guard !pasteStack.isEmpty else { return }; stackPlain = plainText; stackActive = true; stackRequiresExplicitNext = false; prepareStackItem()
        guard accessibilityAllowed, stackMonitor == nil else { return }
        // Physical Cmd-V follows upstream key-up progression; synthetic requests keep bytes until the explicit next action.
        stackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            let paste = event.keyCode == ClipboardKeyboardLayout.pasteKeyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command]
            guard paste else { return }
            Task { @MainActor in guard let self, self.stackActive, Date() > self.suppressStackUntil else { return }
                guard let preparedCount = self.stackPreparedCount else { return }
                guard preparedCount == self.pasteboard.changeCount else { self.clearStack(); return }
                self.advanceStack()
                // Preserve Maccy's physical key-up progression. Synthetic paste
                // requests permanently switch this queue to explicit-next mode.
                if !self.stackRequiresExplicitNext, self.stackActive { self.prepareStackItem() }
            }
        }
    }
    private func prepareStackItem() {
        guard let id = pasteStack.first, let item = items.first(where: { $0.id == id }) else { clearStack(); return }
        if copy(item, plainText: stackPlain) {
            stackPreparedCount = pasteboard.changeCount
            queueState = ClipboardPasteQueue(itemIDs: pasteStack)
            queueState.prepare(ticket: ClipboardPasteTicket(changeCount: pasteboard.changeCount, targetProcessIdentifier: sourceApp?.processIdentifier ?? -1))
        } else { clearStack() }
    }
    private func advanceStack() {
        guard queueState.complete(pasteboard: pasteboard, frontmostProcessIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier) else { return }
        pasteStack = queueState.itemIDs; stackPreparedCount = nil
        if pasteStack.isEmpty { stackActive = false }
        else if stackRequiresExplicitNext { status = "다음 항목은 ‘다음 붙여넣기’를 누르면 준비해요." }
    }
    func pasteNext() {
        if !stackActive { startStack() } else { prepareStackItem() }
        guard let id = pasteStack.first, let item = items.first(where: { $0.id == id }) else { return }
        stackRequiresExplicitNext = true
        paste(item, plainText: stackPlain)
    }
    func showPopup() {
        rememberSource(NSWorkspace.shared.frontmostApplication); query = ""
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 620), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "클립보드"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false; window.level = .floating; window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: ClipboardQuickView(controller: self, dismiss: { [weak self] in self?.panel?.orderOut(nil) }))
            panel = window
        }
        panel?.center(); panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func registerHotkey() {
        if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey = nil
        guard timer != nil, preferences.hotkeyEnabled else { return }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<ClipboardController>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in controller.showPopup() }; return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        let result = RegisterEventHotKey(preferences.hotkeyKeyCode, preferences.hotkeyModifiers, EventHotKeyID(signature: 0x444F4E59, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        if result != noErr { status = "단축키를 등록하지 못했어요. 다른 앱의 단축키와 겹치는지 확인해 주세요." }
    }
    private func persist() {
        guard storeWritable else { return }
        do { try store.save(items) } catch { status = "기록을 저장하지 못했어요: \(error.localizedDescription)" }
    }
    private func savePreferences() { if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "clipboard.preferences") } }
}
