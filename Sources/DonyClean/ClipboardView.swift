import SwiftUI
import AppKit
import Carbon
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
                Button("빠르게 열기") { controller.showPopup() }.buttonStyle(QuietButton())
                Menu {
                    Button(controller.preferences.paused ? "기록 다시 시작" : "기록 일시 정지") { controller.preferences.paused.toggle() }
                    Button("다음 복사 한 번 무시") { controller.ignoreNextCopy = true }
                    Button("클립보드 설정") { showSettings = true }
                    Divider()
                    Button("고정하지 않은 기록 지우기") { controller.clear() }
                    Button("모든 기록 지우기…", role: .destructive) { if ConfirmationDialog.show(title: "모든 기록을 지울까요?", message: "고정한 항목을 포함해 클립보드 기록을 지워요.", action: "모두 지우기", destructive: true, paths: []) { controller.clear(includePinned: true) } }
                } label: { Text("⋯").font(Theme.font(18)).frame(width: 42, height: 42) }.menuStyle(.borderlessButton).frame(width: 42, height: 42).accessibilityLabel("클립보드 작업")
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
                HStack { Text("순서대로 붙여넣기 · \(controller.pasteStack.count)개").font(Theme.font(13, weight: .semibold)); Spacer(); Menu("순서 작업") {
                    Button("순서대로 복사 준비") { controller.startStack() }
                    Button("일반 텍스트로 준비") { controller.startStack(plainText: true) }
                    Button("다음 붙여넣기") { controller.pasteNext() }
                    Button("순서 뒤집기") { controller.reverseStack() }
                    Button("텍스트 합쳐 복사") { controller.copyStackAsText() }
                    Button("순서 비우기") { controller.clearStack() }
                }.menuStyle(.borderlessButton).frame(width: 130) }.panel(16)
            }
            if controller.visibleItems.isEmpty {
                EmptyState(icon: "doc.on.clipboard", title: controller.query.isEmpty ? "복사한 내용이 여기에 저장돼요" : "검색 결과가 없어요", subtitle: "")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(controller.visibleItems) { item in
                        ClipboardItemRow(item: item, controller: controller, edit: { editing = item; editText = item.text ?? "" })
                    }
                }
            }
        }.font(Theme.font(14)).foregroundStyle(Theme.ink)
        .sheet(isPresented: $showSettings) { ClipboardSettingsView(controller: controller).padding(24).frame(width: 560, height: 620).font(Theme.font(14)).background(Theme.canvas).preferredColorScheme(.light) }
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
                Image(nsImage: image).resizable().scaledToFit().frame(width: 48, height: 48).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 10))
            } else { DonyIcon(item.fileURLs.isEmpty ? "doc.on.clipboard" : "folder", size: 22).foregroundStyle(Theme.primary).frame(width: 48, height: 48).background(Theme.blueWash).clipShape(RoundedRectangle(cornerRadius: 10)) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) { if item.pinned { DonyIcon("pin.fill", size: 10).foregroundStyle(Theme.primary) }; Text(item.title).font(Theme.font(14, weight: .medium)).lineLimit(2) }
                Text("\(item.application ?? "앱 정보 없음") · \(item.lastCopiedAt.formatted(date: .abbreviated, time: .shortened)) · \(item.numberOfCopies)회").font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("복사") { controller.copy(item) }.buttonStyle(QuietButton())
            Menu {
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
            } label: { DonyIcon("ellipsis", size: 16).frame(width: 24, height: 32) }.menuStyle(.borderlessButton).frame(width: 24)
        }.panel(16)
    }
}
struct ClipboardSettingsView: View {
    @ObservedObject var controller: ClipboardController
    @Environment(\.dismiss) private var dismiss
    private func listBinding(_ keyPath: WritableKeyPath<ClipboardPreferences, [String]>) -> Binding<String> {
        Binding(get: { controller.preferences[keyPath: keyPath].joined(separator: "\n") }, set: { controller.preferences[keyPath: keyPath] = $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("클립보드 설정").font(Theme.font(22, weight: .bold)); Spacer(); Button("완료") { dismiss() }.buttonStyle(QuietButton()) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Toggle("복사 기록 일시 정지", isOn: $controller.preferences.paused).toggleStyle(DonySwitch())
                    HStack { Text("최대 기록 수"); Spacer(); TextField("200", value: $controller.preferences.limit, format: .number).frame(width: 90).textFieldStyle(.roundedBorder).onChange(of: controller.preferences.limit) { _, value in controller.preferences.limit = max(1, min(10000, value)) } }
                    Text("고정한 항목은 기록 수 제한과 별도로 보존해요.").font(Theme.font(11)).foregroundStyle(Theme.secondary)
                    Text("정렬").font(Theme.font(13, weight: .semibold))
                    DonyChoices(options: ["최근 복사", "처음 복사", "복사 횟수"], selection: Binding(get: { ["최근 복사", "처음 복사", "복사 횟수"][ClipboardSort.allCases.firstIndex(of: controller.preferences.sort) ?? 0] }, set: { controller.preferences.sort = ClipboardSort.allCases[["최근 복사", "처음 복사", "복사 횟수"].firstIndex(of: $0) ?? 0] }))
                    Toggle("고정 항목을 아래에 표시", isOn: $controller.preferences.pinsAtBottom).toggleStyle(DonySwitch())
                    Text("검색 방식").font(Theme.font(13, weight: .semibold))
                    DonyChoices(options: ["포함", "정규식", "유사", "혼합"], selection: Binding(get: { ["포함", "정규식", "유사", "혼합"][ClipboardSearch.allCases.firstIndex(of: controller.preferences.search) ?? 0] }, set: { controller.preferences.search = ClipboardSearch.allCases[["포함", "정규식", "유사", "혼합"].firstIndex(of: $0) ?? 0] }))
                    Divider()
                    Toggle("빠른 창 단축키", isOn: $controller.preferences.hotkeyEnabled).toggleStyle(DonySwitch())
                    ClipboardShortcutRecorder(controller: controller)
                    SettingsActionRow(title: "붙여넣기 접근 권한", actionTitle: controller.accessibilityAllowed ? "허용됨" : "권한 요청", enabled: !controller.accessibilityAllowed) { controller.requestAccessibility() }
                    Text("권한 없이도 기록과 복사를 사용할 수 있어요. 붙여넣기는 마지막으로 사용한 다른 앱에만 실행해요.").font(Theme.font(11)).foregroundStyle(Theme.secondary)
                    Divider()
                    Text("기록할 콘텐츠").font(Theme.font(13, weight: .semibold))
                    ForEach([( "텍스트", ["public.utf8-plain-text"]), ("서식", ["public.rtf", "public.html"]), ("이미지", ["public.png", "public.tiff", "public.jpeg", "public.heic"]), ("파일", ["public.file-url"])], id: \.0) { title, types in
                        Toggle(title, isOn: Binding(get: { types.contains { controller.preferences.enabledTypes.contains($0) } }, set: { enabled in controller.preferences.enabledTypes.removeAll { types.contains($0) }; if enabled { controller.preferences.enabledTypes += types } })).toggleStyle(DonySwitch())
                    }
                    Text("앱 목록 · bundle identifier, 한 줄에 하나").font(Theme.font(13, weight: .semibold))
                    TextEditor(text: listBinding(\.ignoredApps)).frame(height: 65).padding(8).background(Theme.canvas)
                    Toggle("목록의 앱만 기록", isOn: $controller.preferences.onlyListedApps).toggleStyle(DonySwitch())
                    Text("제외할 pasteboard 타입 · 한 줄에 하나").font(Theme.font(13, weight: .semibold))
                    TextEditor(text: listBinding(\.ignoredTypes)).frame(height: 55).padding(8).background(Theme.canvas)
                    Text("제외할 텍스트 정규식 · 한 줄에 하나").font(Theme.font(13, weight: .semibold))
                    TextEditor(text: listBinding(\.ignoredPatterns)).frame(height: 55).padding(8).background(Theme.canvas)
                    Text("보호됨·일시적·자동 생성 타입과 주요 비밀번호 앱은 항상 제외해요. 기록은 이 Mac의 로컬 파일에 저장해요.").font(Theme.font(11)).foregroundStyle(Theme.secondary)
                    if controller.needsRecovery { SettingsActionRow(title: "기록 파일 복구", actionTitle: "보존 후 초기화") { controller.resetUnreadableStore() } }
                    Text("Maccy의 MIT 코드 기반 · Alex Rodionov").font(Theme.font(11)).foregroundStyle(Theme.secondary)
                }.font(Theme.font(14)).padding(.bottom, 12)
            }
        }.font(Theme.font(14)).foregroundStyle(Theme.ink).background(Theme.canvas).preferredColorScheme(.light)
    }
}
struct ClipboardQuickView: View {
    @ObservedObject var controller: ClipboardController
    let dismiss: () -> Void
    @State private var selected = 0
    @FocusState private var searchFocused: Bool
    @State private var monitor: Any?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("클립보드").font(Theme.font(20, weight: .bold)); Spacer(); Chip(text: !controller.pasteStack.isEmpty ? "\(controller.pasteStack.count)개 선택" : (controller.preferences.paused ? "일시 정지" : "\(controller.items.count)개")) }
            TextField("복사한 내용 검색", text: $controller.query).textFieldStyle(.plain).font(Theme.font(14)).padding(12).background(.white).clipShape(RoundedRectangle(cornerRadius: 10)).focused($searchFocused)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(controller.visibleItems.enumerated()), id: \.element.id) { index, item in
                            Button { controller.copy(item); dismiss() } label: {
                                HStack(spacing: 12) {
                                    if controller.pasteStack.contains(item.id) { DonyIcon("checkmark", size: 12).foregroundStyle(Theme.primary) }
                                    if item.pinned { DonyIcon("pin.fill", size: 12).foregroundStyle(Theme.primary) }
                                    if let data = item.imageData, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(width: 35, height: 35) }
                                    Text(item.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    if let letter = item.pinLetter, item.pinned { Text("⌘" + letter.uppercased()).font(Theme.font(11)).foregroundStyle(Theme.secondary) }
                                    else if let numericIndex = controller.visibleItems.filter({ !$0.pinned }).firstIndex(where: { $0.id == item.id }), numericIndex < 9 { Text("⌘\(numericIndex + 1)").font(Theme.font(11)).foregroundStyle(Theme.secondary) }
                                }.font(Theme.font(13)).padding(12).background(selected == index ? Theme.blueWash : .white).clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).id(index)
                        }
                    }
                }.onChange(of: selected) { _, value in reader.scrollTo(value) }
            }
            if !controller.status.isEmpty { Text(controller.status).font(Theme.font(11)).foregroundStyle(Theme.secondary).lineLimit(2) }
            Text("↵ 복사 · ⌥↵ 붙여넣기 · ⇧↵ 순서 준비 · ⌘A 모두 선택 · ⌥S 선택 · ⌥R 역순").font(Theme.font(10)).foregroundStyle(Theme.secondary)
        }.padding(22).background(Theme.canvas).foregroundStyle(Theme.ink)
        .onChange(of: controller.query) { _, _ in selected = 0 }
        .onAppear { searchFocused = true; if monitor == nil { monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in handle(event) ? nil : event } } }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
    private func handle(_ event: NSEvent) -> Bool {
        guard NSApp.keyWindow?.title == "클립보드" else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let values = controller.visibleItems
        if event.keyCode == 53 { dismiss(); return true }
        if event.keyCode == 125 { selected = min(max(0, values.count - 1), selected + 1); return true }
        if event.keyCode == 126 { selected = max(0, selected - 1); return true }
        if let letter = event.charactersIgnoringModifiers?.lowercased(), let pinned = values.first(where: { $0.pinned && $0.pinLetter == letter }), flags.contains(.command) || flags.contains(.option) {
            if flags.contains(.option) { controller.paste(pinned, plainText: flags.contains(.shift)) } else { controller.copy(pinned); dismiss() }; return true
        }
        let numericItems = values.filter { !$0.pinned }
        if let character = event.charactersIgnoringModifiers, let number = Int(character), (1...9).contains(number), number <= numericItems.count {
            if flags.contains(.option) { controller.paste(numericItems[number - 1], plainText: flags.contains(.shift)); return true }
            if flags.contains(.command) { controller.copy(numericItems[number - 1]); dismiss(); return true }
        }
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "a" { controller.selectStack(values); return true }
        if flags.contains(.option), event.charactersIgnoringModifiers?.lowercased() == "r" { controller.reverseStack(); return true }
        if flags.contains([.option, .command]), event.keyCode == 51 { controller.clear(includePinned: flags.contains(.shift)); selected = 0; return true }
        guard values.indices.contains(selected) else { return false }; let item = values[selected]
        if flags.contains(.option), event.charactersIgnoringModifiers?.lowercased() == "s" { controller.toggleStack(item); return true }
        if event.keyCode == 36 || event.keyCode == 76 { if flags.contains(.shift), !flags.contains(.option), !controller.pasteStack.isEmpty { controller.startStack(); dismiss() } else if flags.contains(.option) { controller.paste(item, plainText: flags.contains(.shift)) } else { controller.copy(item); dismiss() }; return true }
        if flags.contains(.option), event.keyCode == 51 { controller.delete(item); selected = min(selected, max(0, values.count - 2)); return true }
        if flags.contains(.option), event.charactersIgnoringModifiers?.lowercased() == "p" { controller.setPinned(item); return true }
        return false
    }
}

struct ClipboardShortcutRecorder: View {
    @ObservedObject var controller: ClipboardController
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        HStack {
            Text("빠른 창 단축키").font(Theme.font(14, weight: .medium))
            Spacer()
            Button(recording ? "조합키 입력 · Esc 취소" : shortcutName) { beginRecording() }.buttonStyle(QuietButton())
        }.onDisappear { endRecording() }
    }
    private var shortcutName: String {
        let mods = controller.preferences.hotkeyModifiers
        return (mods & UInt32(controlKey) != 0 ? "⌃" : "") + (mods & UInt32(optionKey) != 0 ? "⌥" : "") + (mods & UInt32(shiftKey) != 0 ? "⇧" : "") + (mods & UInt32(cmdKey) != 0 ? "⌘" : "") + ClipboardKeyboardLayout.name(for: UInt16(controller.preferences.hotkeyKeyCode))
    }
    private func beginRecording() {
        endRecording(); recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { endRecording(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            controller.preferences.hotkeyKeyCode = UInt32(event.keyCode)
            controller.preferences.hotkeyModifiers = modifiers
            endRecording(); return nil
        }
    }
    private func endRecording() { recording = false; if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}
