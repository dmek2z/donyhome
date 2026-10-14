import SwiftUI
import AppKit
import Carbon
import ServiceManagement
import DonyCore

struct ClipboardView: View {
    @ObservedObject var controller: ClipboardController
    @State private var editing: ClipboardItem?
    @State private var editText = ""
    @State private var showSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                PageHeader(title: "클립보드")
                Spacer()
                Button("설정") { showSettings = true }.buttonStyle(QuietButton())
                Button("빠르게 열기") { controller.showPopup() }.buttonStyle(QuietButton())
                DonyIconMenu(title: "클립보드 작업", size: Theme.controlHeight) {
                    Button(controller.preferences.paused ? "기록 다시 시작" : "기록 일시 정지") { controller.preferences.paused.toggle() }
                    Button("다음 복사 한 번 무시") { controller.ignoreNextCopy = true }
                    Divider()
                    Button("고정하지 않은 기록 지우기") { controller.clear() }
                    Button("전체 지우기…", role: .destructive) { controller.confirmClearAll() }.disabled(!controller.canClearAll)
                }
            }.frame(height: 42)
            HStack(spacing: 12) {
                DonySearchField(placeholder: "텍스트 · 파일 이름 검색", text: $controller.query)
                Chip(text: controller.preferences.paused ? "기록 일시 정지" : "\(controller.items.count)개 기록", color: controller.preferences.paused ? Theme.amber : Theme.primary)
            }
            if !controller.status.isEmpty {
                HStack { Text(controller.status).font(Theme.font(12)).foregroundStyle(Theme.secondary); Spacer() }.panel(16)
            }
            if controller.ignoreNextCopy { Text("다음 복사는 기록하지 않아요.").font(Theme.font(12)).foregroundStyle(Theme.amber) }
            if !controller.pasteStack.isEmpty {
                HStack { Text("순서대로 붙여넣기 · \(controller.pasteStack.count)개").font(Theme.font(13, weight: .semibold)); Spacer(); Button("다음 붙여넣기") { controller.pasteNext() }.buttonStyle(QuietButton()); DonyIconMenu(title: "순서 작업") {
                    Button("순서대로 복사 준비") { controller.startStack() }
                    Button("일반 텍스트로 준비") { controller.startStack(plainText: true) }
                    Button("순서 뒤집기") { controller.reverseStack() }
                    Button("텍스트 합쳐 복사") { controller.copyStackAsText() }
                    Button("순서 비우기") { controller.clearStack() }
                } }.panel(16)
            }
            if controller.visibleItems.isEmpty {
                EmptyState(icon: "doc.on.clipboard", title: controller.query.isEmpty ? "복사한 내용이 여기에 저장돼요" : "검색 결과가 없어요", subtitle: "")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(controller.visibleItems) { item in
                        ClipboardItemRow(item: item, controller: controller, edit: { editing = item; editText = item.text ?? "" })
                        if item.id != controller.visibleItems.last?.id { Divider().padding(.leading, 60) }
                    }
                }.panel(0)
            }
        }.font(Theme.font(14)).foregroundStyle(Theme.ink)
        .sheet(isPresented: $showSettings) { ClipboardSettingsView(controller: controller).padding(24).frame(width: Theme.settingsWidth, height: Theme.settingsHeight).font(Theme.font(14)).background(Theme.canvas).preferredColorScheme(.light) }
        .sheet(item: $editing) { item in
            VStack(alignment: .leading, spacing: 18) {
                Text("텍스트 편집").font(Theme.font(22, weight: .bold))
                Text("저장하면 일반 텍스트로 바뀌어요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                TextEditor(text: $editText).font(Theme.font(14)).frame(minHeight: 250).padding(8).background(Theme.canvas)
                HStack { Spacer(); Button("취소") { editing = nil }.buttonStyle(QuietButton()); Button("저장") { controller.edit(item, text: editText); editing = nil }.buttonStyle(PrimaryButton()) }
            }.padding(24).frame(width: 560).background(Theme.canvas).preferredColorScheme(.light)
        }

    }
}
struct ClipboardItemRow: View {
    let item: ClipboardItem
    @ObservedObject var controller: ClipboardController
    var edit: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            if let data = item.imageData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 32).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 10))
            } else { DonyIcon(item.fileURLs.isEmpty ? "doc.on.clipboard" : "folder", size: 18).foregroundStyle(Theme.primary).frame(width: 32, height: 32).background(Theme.blueWash).clipShape(RoundedRectangle(cornerRadius: 10)) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) { if item.pinned { DonyIcon("pin.fill", size: 10).foregroundStyle(Theme.primary) }; Text(item.title).font(Theme.font(14, weight: .medium)).lineLimit(1).truncationMode(.middle).help(item.text ?? item.title) }
                Text("\(item.application ?? "앱 정보 없음") · \(item.lastCopiedAt.formatted(date: .abbreviated, time: .shortened)) · \(item.numberOfCopies)회").font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("복사") { controller.copy(item) }.buttonStyle(QuietButton())
            DonyIconMenu(title: "복사 항목 작업") {
                Button("붙여넣기") { controller.paste(item) }
                Button("일반 텍스트로 복사") { controller.copy(item, plainText: true) }
                Button("일반 텍스트로 붙여넣기") { controller.paste(item, plainText: true) }
                Divider()
                Button(item.pinned ? "고정 해제" : "고정") { controller.setPinned(item) }
                if item.pinned {
                    Menu("고정 단축키 · " + (item.pinLetter?.uppercased() ?? "없음")) {
                        ForEach(controller.availablePinLetters, id: \.self) { letter in Button("⌘" + letter.uppercased()) { controller.assignPinLetter(item, letter: letter) } }
                    }
                    Button("고정 순서 위로") { controller.movePin(item, up: true) }
                    Button("고정 순서 아래로") { controller.movePin(item, up: false) }
                }
                if item.text != nil { Button("텍스트 편집…", action: edit) }
                Button(controller.pasteStack.contains(item.id) ? "붙여넣기 순서에서 제거" : "붙여넣기 순서에 추가") { controller.toggleStack(item) }
                Button("삭제", role: .destructive) { controller.delete(item) }
            }
        }.padding(.horizontal, 16).frame(height: Theme.listRowHeight).contentShape(Rectangle())
    }
}
struct ClipboardSettingsView: View {
    @ObservedObject var controller: ClipboardController
    var closeAction: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    private func listBinding(_ keyPath: WritableKeyPath<ClipboardPreferences, [String]>) -> Binding<String> {
        Binding(get: { controller.preferences[keyPath: keyPath].joined(separator: "\n") }, set: { controller.preferences[keyPath: keyPath] = $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }
    @State private var choosingPin: ClipboardItem?
    @State private var category = "일반"
    @State private var exclusion = "앱"
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    private func appearance<Value>(_ key: WritableKeyPath<ClipboardAppearance, Value>) -> Binding<Value> {
        Binding(get: { (controller.preferences.appearance ?? ClipboardAppearance())[keyPath: key] }, set: { value in var settings = controller.preferences.appearance ?? ClipboardAppearance(); settings[keyPath: key] = value; controller.preferences.appearance = settings })
    }
    private func behavior(_ key: WritableKeyPath<ClipboardBehavior, Bool>) -> Binding<Bool> {
        Binding(get: { (controller.preferences.behavior ?? ClipboardBehavior())[keyPath: key] }, set: { value in var settings = controller.preferences.behavior ?? ClipboardBehavior(); settings[keyPath: key] = value; controller.preferences.behavior = settings })
    }
    private func pinKeySheet(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text("고정 단축키").font(Theme.font(20, weight: .semibold)); Spacer(); DonyTextAction(title: "완료") { choosingPin = nil } }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 12) {
                ForEach(controller.availablePinLetters, id: \.self) { letter in
                    Button("⌘" + letter.uppercased()) { controller.assignPinLetter(item, letter: letter); choosingPin = nil }.buttonStyle(QuietButton())
                }
            }
        }.padding(24).frame(width: 520).foregroundStyle(Theme.body).background(Theme.canvas)
    }
    private func choices(_ title: String, options: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(Theme.font(14, weight: .medium)); DonyChoices(options: options, selection: selection) }
    }
    var body: some View {
        Group {
            if let item = choosingPin { pinKeySheet(item) }
            else if let item = pinEditing {
                VStack(spacing: 16) {
                    Text("고정 텍스트 편집").font(Theme.font(20, weight: .bold))
                    TextEditor(text: $pinText).frame(height: 220)
                    HStack { Spacer(); Button("취소") { pinEditing = nil }.buttonStyle(QuietButton()); Button("저장") { controller.edit(item, text: pinText); pinEditing = nil }.buttonStyle(PrimaryButton()) }
                }.padding(24).frame(width: 520)
            } else {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("클립보드 설정").font(Theme.font(22, weight: .bold)); Spacer(); Button("완료") { if let closeAction { closeAction() } else { dismiss() } }.buttonStyle(QuietButton()) }
            DonyTabs(options: ["일반", "보관", "모양", "고정", "제외", "고급"], selection: $category)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch category {
                    case "일반":
                        Toggle("로그인할 때 도니홈 실행", isOn: $loginEnabled).toggleStyle(DonySwitch()).onChange(of: loginEnabled) { _, value in do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { loginEnabled = SMAppService.mainApp.status == .enabled; controller.status = error.localizedDescription } }
                        Divider()
                        Toggle("빠른 창 단축키", isOn: $controller.preferences.hotkeyEnabled).toggleStyle(DonySwitch())
                        ClipboardShortcutRecorder(controller: controller)
                        if let issue = controller.hotkeyError { Text(issue).font(Theme.font(12)).foregroundStyle(Theme.red) }
                        else if controller.hotkeyRegistered { Chip(text: "전역 단축키 사용 가능", color: Theme.success) }
                        ClipboardShortcutRecorder(controller: controller, kind: "고정")
                        ClipboardShortcutRecorder(controller: controller, kind: "삭제")
                        choices("검색 방식", options: ["포함", "정규식", "유사", "혼합"], selection: Binding(get: { ["포함", "정규식", "유사", "혼합"][ClipboardSearch.allCases.firstIndex(of: controller.preferences.search) ?? 0] }, set: { controller.preferences.search = ClipboardSearch.allCases[["포함", "정규식", "유사", "혼합"].firstIndex(of: $0) ?? 0] }))
                        Divider()
                        Toggle("선택하면 바로 붙여넣기", isOn: behavior(\.pasteAutomatically)).toggleStyle(DonySwitch())
                        Toggle("서식 없이 붙여넣기", isOn: behavior(\.plainText)).toggleStyle(DonySwitch())
                        SettingsActionRow(title: "붙여넣기 접근 권한", actionTitle: controller.accessibilityAllowed ? "허용됨" : "권한 요청", enabled: !controller.accessibilityAllowed) { controller.requestAccessibility() }
                    case "보관":
                        ForEach([( "텍스트", ["public.utf8-plain-text"]), ("서식", ["public.rtf", "public.html"]), ("이미지", ["public.png", "public.tiff", "public.jpeg", "public.heic"]), ("파일", ["public.file-url"])], id: \.0) { title, types in
                            Toggle(title, isOn: Binding(get: { types.contains { controller.preferences.enabledTypes.contains($0) } }, set: { enabled in controller.preferences.enabledTypes.removeAll { types.contains($0) }; if enabled { controller.preferences.enabledTypes += types } })).toggleStyle(DonySwitch())
                        }
                        Divider()
                        HStack { Text("최대 기록 수"); Spacer(); TextField("200", value: $controller.preferences.limit, format: .number).frame(width: 90).textFieldStyle(.roundedBorder).onChange(of: controller.preferences.limit) { _, value in controller.preferences.limit = max(1, min(10000, value)) }; Text("개") }
                        choices("정렬 기준", options: ["최근 복사", "처음 복사", "복사 횟수"], selection: Binding(get: { ["최근 복사", "처음 복사", "복사 횟수"][ClipboardSort.allCases.firstIndex(of: controller.preferences.sort) ?? 0] }, set: { controller.preferences.sort = ClipboardSort.allCases[["최근 복사", "처음 복사", "복사 횟수"].firstIndex(of: $0) ?? 0] }))
                        Text("기록 용량 · " + DisplayFormat.bytes(Int64(controller.items.reduce(0) { $0 + $1.byteCount }))).font(Theme.font(12)).foregroundStyle(Theme.secondary)
                    case "모양":
                        choices("빠른 창 위치", options: ["커서", "중앙"], selection: appearance(\.popupPosition))
                        HStack { Text("이미지 높이"); Spacer(); Slider(value: Binding(get: { Double(appearance(\.imageHeight).wrappedValue) }, set: { appearance(\.imageHeight).wrappedValue = Int($0) }), in: 24...64, step: 4).frame(width: 180); Text("\(appearance(\.imageHeight).wrappedValue)pt").frame(width: 48) }
                        HStack { Text("미리보기 지연"); Spacer(); TextField("1500", value: appearance(\.previewDelay), format: .number).frame(width: 90).textFieldStyle(.roundedBorder).onChange(of: controller.preferences.appearance?.previewDelay) { _, value in if let value { appearance(\.previewDelay).wrappedValue = max(0, min(5000, value)) } }; Text("ms") }
                        Divider()
                        Toggle("특수 기호 표시", isOn: appearance(\.showSpecialCharacters)).toggleStyle(DonySwitch())
                        Toggle("앱 아이콘 표시", isOn: appearance(\.showAppIcons)).toggleStyle(DonySwitch())
                        Toggle("빠른 창 제목 표시", isOn: appearance(\.showTitle)).toggleStyle(DonySwitch())
                        Toggle("빠른 창 하단 메뉴 표시", isOn: appearance(\.showFooter)).toggleStyle(DonySwitch())
                    case "고정":
                        Toggle("고정 항목을 아래에 표시", isOn: $controller.preferences.pinsAtBottom).toggleStyle(DonySwitch())
                        Divider()
                        if !controller.items.contains(where: \.pinned) { Text("고정한 항목이 없어요").foregroundStyle(Theme.secondary) }
                        ForEach(controller.pinnedItems) { item in
                            HStack { Button(item.pinLetter.map { "⌘" + $0.uppercased() } ?? "키 선택") { choosingPin = item }.buttonStyle(QuietButton()); TextField("제목", text: Binding(get: { item.title }, set: { controller.renamePin(item, title: $0) })).textFieldStyle(.roundedBorder); Button("편집") { pinEditing = item; pinText = item.text ?? "" }.buttonStyle(QuietButton()).disabled(item.text == nil); DonyIconMenu(title: "고정 항목 작업") { Button("위로") { controller.movePin(item, up: true) }; Button("아래로") { controller.movePin(item, up: false) }; Button("고정 해제") { controller.setPinned(item) } } }.frame(height: Theme.listRowHeight)
                        }
                    case "제외":
                        DonyChoices(options: ["앱", "클립보드 타입", "정규식"], selection: $exclusion)
                        if exclusion == "앱" {
                            TextEditor(text: listBinding(\.ignoredApps)).frame(height: 180).padding(8).background(Theme.canvas)
                            HStack { Text("bundle identifier · 한 줄에 하나").font(Theme.font(12)).foregroundStyle(Theme.secondary); Spacer(); Button("앱 추가") { addExcludedApp() }.buttonStyle(QuietButton()) }
                            Toggle("목록의 앱만 기록", isOn: $controller.preferences.onlyListedApps).toggleStyle(DonySwitch())
                        } else if exclusion == "클립보드 타입" {
                            TextEditor(text: listBinding(\.ignoredTypes)).frame(height: 180).padding(8).background(Theme.canvas)
                            Text("타입을 한 줄에 하나 입력하세요").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        } else {
                            TextEditor(text: listBinding(\.ignoredPatterns)).frame(height: 180).padding(8).background(Theme.canvas)
                            Text("패턴을 한 줄에 하나 입력하세요").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        }
                    default:
                        Toggle("복사 기록 일시 정지", isOn: $controller.preferences.paused).toggleStyle(DonySwitch())
                        SettingsActionRow(title: "다음 복사 한 번 무시", actionTitle: "무시") { controller.ignoreNextCopy = true }
                        Divider()
                        Toggle("도니홈 종료 시 기록 지우기", isOn: behavior(\.clearOnQuit)).toggleStyle(DonySwitch())
                        Toggle("종료 시 시스템 클립보드도 지우기", isOn: behavior(\.clearSystemOnQuit)).toggleStyle(DonySwitch())
                        Text("고정한 기록도 지워요. 지운 기록은 복구할 수 없어요.").font(Theme.font(12)).foregroundStyle(Theme.secondary)
                        if controller.needsRecovery { SettingsActionRow(title: "기록 파일 복구", actionTitle: "초기화 검토") { controller.resetUnreadableStore() } }
                    }
                }.font(Theme.font(14)).frame(maxWidth: .infinity, alignment: .leading).panel(20).padding(.bottom, 12)
            }
        }
            }
        }.font(Theme.font(14)).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
    }

    @State private var pinEditing: ClipboardItem?
    @State private var pinText = ""
    private func addExcludedApp() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.canChooseFiles = true; picker.allowsMultipleSelection = true; picker.allowedContentTypes = [.application]; picker.directoryURL = URL(fileURLWithPath: "/Applications")
        guard picker.runModal() == .OK else { return }
        for url in picker.urls { if let id = Bundle(url: url)?.bundleIdentifier, !controller.preferences.ignoredApps.contains(id) { controller.preferences.ignoredApps.append(id) } }
    }

}
struct ClipboardQuickView: View {
    @ObservedObject var controller: ClipboardController
    let dismiss: () -> Void
    @State private var selected = 0
    @FocusState private var searchFocused: Bool
    @State private var monitorID = UUID()
    @State private var hovered: UUID?
    @State private var preview: ClipboardItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { if controller.preferences.appearance?.showTitle != false { Text("클립보드").font(Theme.font(20, weight: .bold)) }; Spacer(); Chip(text: !controller.pasteStack.isEmpty ? "\(controller.pasteStack.count)개 선택" : (controller.preferences.paused ? "일시 정지" : "\(controller.items.count)개")) }
            TextField("복사한 내용 검색", text: $controller.query).textFieldStyle(.plain).font(Theme.font(14)).padding(12).background(.white).clipShape(RoundedRectangle(cornerRadius: 10)).focused($searchFocused)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if controller.quickItems.isEmpty { Text(controller.query.isEmpty ? "아직 복사 기록이 없어요" : "검색 결과가 없어요").font(Theme.font(13)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, minHeight: 40) }
                        ForEach(Array(controller.quickItems.enumerated()), id: \.element.id) { index, item in
                            Button { controller.selectItem(item, flags: NSApp.currentEvent?.modifierFlags ?? []) } label: {
                                HStack(spacing: 12) {
                                    if controller.isCurrentCopy(item) { DonyIcon("checkmark", size: 12).foregroundStyle(Theme.success).accessibilityLabel("현재 클립보드") }
                                    if controller.pasteStack.contains(item.id) { DonyIcon("checkmark", size: 12).foregroundStyle(Theme.primary) }
                                    if item.pinned { DonyIcon("pin.fill", size: 12).foregroundStyle(Theme.primary) }
                                    if let data = item.imageData, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(width: CGFloat(controller.preferences.appearance?.imageHeight ?? 40), height: CGFloat(controller.preferences.appearance?.imageHeight ?? 40)) }
                                    if controller.preferences.appearance?.showAppIcons == true, let id = item.application, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20) }
                                    Text(displayTitle(item.title)).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                                    if let letter = item.pinLetter, item.pinned { Text("⌘" + letter.uppercased()).font(Theme.font(11)).foregroundStyle(Theme.secondary) }
                                    else if let numericIndex = controller.quickItems.filter({ !$0.pinned }).firstIndex(where: { $0.id == item.id }), numericIndex < 9 { Text("⌘\(numericIndex + 1)").font(Theme.font(11)).foregroundStyle(Theme.secondary) }
                                }.font(Theme.font(13)).padding(.horizontal, 12).frame(height: item.imageData == nil ? Theme.quickRowHeight : CGFloat(controller.preferences.appearance?.imageHeight ?? 40) + 8).background(selected == index ? Theme.blueWash : .white).clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).accessibilityValue(controller.isCurrentCopy(item) ? "현재 클립보드" : "").id(index).onHover { active in if active { selected = index; hovered = item.id } else if hovered == item.id { hovered = nil; preview = nil } }
                        }
                    }
                }.onChange(of: selected) { _, value in reader.scrollTo(value) }
            }
            if !controller.status.isEmpty { Text(controller.status).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(2) }
            if controller.preferences.appearance?.showFooter != false {
                Divider()
                HStack {
                    Button("설정") { controller.showQuickSettings() }.buttonStyle(QuietButton())
                    Spacer()
                    Text("↵ 선택 · ⌥↵ 붙여넣기").font(Theme.font(11)).foregroundStyle(Theme.secondary)
                    Button("전체 지우기", role: .destructive) { controller.confirmClearAll() }.buttonStyle(QuietButton()).disabled(!controller.canClearAll)
                    DonyIconMenu(title: "기록 작업") { Button("고정하지 않은 기록 지우기") { controller.clear() }; Button("일시 정지") { controller.preferences.paused.toggle() } }
                }
            }
        }.padding(22).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 20)).foregroundStyle(Theme.ink)
        .onChange(of: controller.popupGeneration) { _, _ in selected = 0; searchFocused = true; hovered = nil; preview = nil }
        .task(id: hovered) {
            preview = nil
            guard let id = hovered, !controller.quickSettingsShown else { return }
            try? await Task.sleep(for: .milliseconds(controller.preferences.appearance?.previewDelay ?? 1500))
            guard !Task.isCancelled, hovered == id else { return }
            preview = controller.items.first { $0.id == id }
        }
        .popover(item: $preview) { item in
            ScrollView { if let data = item.imageData, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() } else { Text(item.text ?? item.title).font(Theme.font(13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }.padding(16).frame(width: 360, height: 240)
        }
        .onChange(of: controller.quickSettingsShown) { _, shown in if shown { hovered = nil; preview = nil } }
        .onChange(of: controller.query) { _, _ in selected = 0; hovered = nil; preview = nil }
        .onAppear { searchFocused = true; controller.installPopupKeyMonitor(id: monitorID, handle: handle) }
        .onDisappear { controller.removePopupKeyMonitor(id: monitorID) }
    }
    private func matches(_ event: NSEvent, shortcut: ClipboardKeyShortcut) -> Bool {
        let flags = event.modifierFlags
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return UInt32(event.keyCode) == shortcut.keyCode && value == shortcut.modifiers
    }
    private func displayTitle(_ value: String) -> String {
        guard controller.preferences.appearance?.showSpecialCharacters == true else { return value.replacingOccurrences(of: "\n", with: " ") }
        return value.replacingOccurrences(of: "\t", with: "⇥").replacingOccurrences(of: "\n", with: "↵").replacingOccurrences(of: " ", with: "·")
    }
    private func handle(_ event: NSEvent) -> Bool {
        guard controller.handlesPopupEvent(event) else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let values = controller.quickItems
        if flags.contains(.command), (event.keyCode == 43 || event.charactersIgnoringModifiers == ",") { controller.showQuickSettings(); return true }
        if event.keyCode == 53 { dismiss(); return true }
        if event.keyCode == 125 { selected = min(max(0, values.count - 1), selected + 1); return true }
        if event.keyCode == 126 { selected = max(0, selected - 1); return true }
        if values.indices.contains(selected) {
            let item = values[selected]
            if matches(event, shortcut: controller.preferences.deleteShortcut ?? ClipboardKeyShortcut(keyCode: 51, modifiers: UInt32(optionKey))) { controller.delete(item); selected = min(selected, max(0, values.count - 2)); return true }
            if matches(event, shortcut: controller.preferences.pinShortcut ?? ClipboardKeyShortcut(keyCode: 35, modifiers: UInt32(optionKey))) { controller.setPinned(item); return true }
        }
        if let letter = event.charactersIgnoringModifiers?.lowercased(), let pinned = values.first(where: { $0.pinned && $0.pinLetter == letter }), flags.contains(.command) || flags.contains(.option) {
            controller.selectItem(pinned, flags: flags); return true
        }
        let numericItems = values.filter { !$0.pinned }
        if let character = event.charactersIgnoringModifiers, let number = Int(character), (1...9).contains(number), number <= numericItems.count {
            if flags.contains(.option) { controller.selectItem(numericItems[number - 1], flags: flags); return true }
            if flags.contains(.command) { _ = controller.copyShortcut(character); return true }
        }
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "a" { controller.selectStack(values); return true }
        if flags.contains(.option), event.charactersIgnoringModifiers?.lowercased() == "r" { controller.reverseStack(); return true }
        if flags.contains([.option, .command]), event.keyCode == 51 { controller.clear(includePinned: flags.contains(.shift)); selected = 0; return true }
        guard values.indices.contains(selected) else { return false }; let item = values[selected]
        if flags.contains(.option), event.charactersIgnoringModifiers?.lowercased() == "s" { controller.toggleStack(item); return true }
        if event.keyCode == 36 || event.keyCode == 76 { if flags.contains(.shift), !flags.contains(.option), !controller.pasteStack.isEmpty { controller.startStack(); dismiss() } else { controller.selectItem(item, flags: flags) }; return true }
        return false
    }
}

struct ClipboardShortcutRecorder: View {
    @ObservedObject var controller: ClipboardController
    var kind = "열기"
    @State private var recorderID = UUID()
    @State private var recorderWindow: Int?
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsActionRow(title: kind == "열기" ? "빠른 창 단축키" : kind + " 단축키", actionTitle: recording ? "입력 중" : shortcutName) { beginRecording() }
            if recording { Text("조합키를 누르세요 · Esc 취소").font(Theme.font(12)).foregroundStyle(Theme.secondary) }
        }.background(ClipboardRecorderWindow { recorderWindow = $0 })
            .onDisappear { endRecording() }
    }
    private var shortcutName: String {
        let shortcut = kind == "고정" ? (controller.preferences.pinShortcut ?? ClipboardKeyShortcut(keyCode: 35, modifiers: UInt32(optionKey))) : kind == "삭제" ? (controller.preferences.deleteShortcut ?? ClipboardKeyShortcut(keyCode: 51, modifiers: UInt32(optionKey))) : ClipboardKeyShortcut(keyCode: controller.preferences.hotkeyKeyCode, modifiers: controller.preferences.hotkeyModifiers)
        let mods = shortcut.modifiers
        return (mods & UInt32(controlKey) != 0 ? "⌃" : "") + (mods & UInt32(optionKey) != 0 ? "⌥" : "") + (mods & UInt32(shiftKey) != 0 ? "⇧" : "") + (mods & UInt32(cmdKey) != 0 ? "⌘" : "") + ClipboardKeyboardLayout.name(for: UInt16(shortcut.keyCode))
    }
    private func beginRecording() {
        endRecording(); recording = true
        controller.registerShortcutRecorder(id: recorderID, cancel: { endRecording() })
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window, window.isVisible, window.windowNumber == recorderWindow else { return event }
            if event.keyCode == 53 { endRecording(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            let shortcut = ClipboardKeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            if kind == "고정" { controller.preferences.pinShortcut = shortcut }
            else if kind == "삭제" { controller.preferences.deleteShortcut = shortcut }
            else { controller.preferences.hotkeyKeyCode = shortcut.keyCode; controller.preferences.hotkeyModifiers = shortcut.modifiers }
            endRecording(); return nil
        }
    }
    private func endRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        controller.unregisterShortcutRecorder(id: recorderID)
    }
}


private struct ClipboardRecorderWindow: NSViewRepresentable {
    let onChange: (Int?) -> Void
    func makeNSView(context: Context) -> ClipboardRecorderWindowView {
        let view = ClipboardRecorderWindowView(); view.onChange = onChange; return view
    }
    func updateNSView(_ view: ClipboardRecorderWindowView, context: Context) { view.onChange = onChange }
}
private final class ClipboardRecorderWindowView: NSView {
    var onChange: ((Int?) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let number = window?.windowNumber
        DispatchQueue.main.async { [weak self] in self?.onChange?(number) }
    }
}
