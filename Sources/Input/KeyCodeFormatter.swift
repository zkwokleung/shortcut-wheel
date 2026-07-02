import Carbon.HIToolbox
import CoreGraphics

/// Human-readable name for a virtual key code, for display in shortcut UI. Special
/// keys use a fixed table; character keys are resolved against the *current* keyboard
/// layout (so "Y"/"Z" follow QWERTZ, etc.) via `UCKeyTranslate`.
enum KeyCodeFormatter {
    static func name(for keyCode: CGKeyCode) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        if let character = character(for: keyCode) { return character }
        return "Key \(keyCode)"
    }

    /// Keys with no printable character (or whose glyph is clearer as a word/symbol).
    private static let specialKeys: [Int: String] = {
        var keys: [Int: String] = [
            kVK_Space: "Space",
            kVK_Return: "Return",
            kVK_ANSI_KeypadEnter: "Enter",
            kVK_Tab: "Tab",
            kVK_Escape: "Esc",
            kVK_Delete: "Delete",
            kVK_ForwardDelete: "⌦",
            kVK_Help: "Help",
            kVK_Home: "Home",
            kVK_End: "End",
            kVK_PageUp: "Page Up",
            kVK_PageDown: "Page Down",
            kVK_LeftArrow: "←",
            kVK_RightArrow: "→",
            kVK_DownArrow: "↓",
            kVK_UpArrow: "↑",
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, code) in functionKeys.enumerated() { keys[code] = "F\(index + 1)" }
        return keys
    }()

    /// Unicode layout data for the active layout, or the ASCII-capable one as a
    /// fallback — the current layout exposes none when a non-Roman IME (e.g. a CJK
    /// input method) is active, which would otherwise drop character keys to "Key N".
    private static func unicodeLayoutData() -> UnsafeMutableRawPointer? {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            return data
        }
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            return data
        }
        return nil
    }

    private static func character(for keyCode: CGKeyCode) -> String? {
        guard let layoutPointer = unicodeLayoutData() else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0, // no modifiers — we want the base key glyph
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let glyph = String(utf16CodeUnits: characters, count: length)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return glyph.isEmpty ? nil : glyph.uppercased()
        }
    }
}
