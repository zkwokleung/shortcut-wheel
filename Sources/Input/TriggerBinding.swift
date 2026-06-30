import CoreGraphics

/// What the user holds to open the wheel. `code` is interpreted per `kind`:
/// - `.key`: a `CGKeyCode` (virtual key code).
/// - `.modifier`: a raw `CGEventFlags` mask for a single modifier (e.g. right option).
/// - `.mouseButton`: a mouse button number (2 = first side button, etc.).
struct TriggerBinding: Codable, Equatable {
    enum Kind: String, Codable {
        case key
        case modifier
        case mouseButton
    }

    var kind: Kind
    var code: UInt64
    /// When true, the trigger's own events are consumed so they don't reach the
    /// focused app. Safe to leave off for uncommon triggers.
    var swallowEvent: Bool

    /// Device-dependent flag bits that distinguish left vs right modifier keys.
    /// `CGEventFlags.maskAlternate` (etc.) is set for *either* side; these bits
    /// pin the binding to one physical key. Values from IOKit's NX_DEVICE*KEYMASK.
    static let rightOptionMask: UInt64 = CGEventFlags.maskAlternate.rawValue | 0x0000_0040
    static let leftOptionMask: UInt64 = CGEventFlags.maskAlternate.rawValue | 0x0000_0020

    /// Right Option — uncommon enough to not hijack normal typing.
    static let rightOption = TriggerBinding(
        kind: .modifier,
        code: rightOptionMask,
        swallowEvent: false
    )

    var flags: CGEventFlags { CGEventFlags(rawValue: code) }
    var keyCode: CGKeyCode { CGKeyCode(truncatingIfNeeded: code) }
    /// Clamped so a malformed/high-bit `code` can't become a negative button number.
    var mouseButtonNumber: Int64 { Int64(clamping: code) }

    var displayName: String {
        switch kind {
        case .modifier:
            switch code {
            case Self.rightOptionMask: return "Right Option (⌥)"
            case Self.leftOptionMask: return "Left Option (⌥)"
            case CGEventFlags.maskAlternate.rawValue: return "Option (⌥)"
            case CGEventFlags.maskCommand.rawValue: return "Command (⌘)"
            case CGEventFlags.maskControl.rawValue: return "Control (⌃)"
            case CGEventFlags.maskShift.rawValue: return "Shift (⇧)"
            default: return "Modifier"
            }
        case .key:
            return "Key \(code)"
        case .mouseButton:
            // macOS button numbers are 0-based; the UI labels them 1-based (button
            // number 3 = "Mouse Button 4"), matching the SettingsView presets.
            return "Mouse Button \(code + 1)"
        }
    }
}
