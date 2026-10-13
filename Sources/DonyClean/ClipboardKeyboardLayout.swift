// Adapted from Maccy/KeyboardLayout.swift, Copyright (c) 2025 Alex Rodionov, MIT.
// See Resources/Clipboard/Maccy-LICENSE.txt.
import Carbon

struct ClipboardKeyboardLayout {
    static func name(for key: UInt16) -> String {
        let known: [UInt16: String] = [36: "↵", 48: "⇥", 49: "Space", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        if let name = known[key] { return name }
        let input = TISCopyCurrentKeyboardLayoutInputSource().takeUnretainedValue()
        guard let pointer = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData) else { return "Key \(key)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return "Key \(key)" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var state: UInt32 = 0; var length = 0; var chars = [UniChar](repeating: 0, count: 4)
        let result = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &state, 4, &length, &chars)
        if result == noErr, length > 0 { return String(utf16CodeUnits: chars, count: length).uppercased() }
        return "Key \(key)"
    }
    static var pasteKeyCode: CGKeyCode {
        let input = TISCopyCurrentKeyboardLayoutInputSource().takeUnretainedValue()
        if let pointer = TISGetInputSourceProperty(input, kTISPropertyLocalizedName) {
            let name = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
            // Maccy preserves QWERTY V for command-switching layouts such as Dvorak – QWERTY ⌘.
            if name.hasSuffix("⌘") { return 9 }
        }
        guard let pointer = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData) else { return 9 }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return 9 }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        for key in UInt16(0)...UInt16(127) {
            var state: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let result = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &state, 4, &length, &chars)
            if result == noErr, length == 1, chars[0] == 118 { return key }
        }
        return 9
    }
}
