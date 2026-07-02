import CoreGraphics
import Foundation

/// What the user holds to open the wheel. `code` is interpreted per `kind`:
/// - `.key`: a `CGKeyCode` (virtual key code).
/// - `.modifier`: a raw `CGEventFlags` mask. A single bit is one modifier; several
///   ORed bits is a chord (e.g. ⌃⌥) that requires all of them held together.
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
    /// Seconds the trigger must be held before the wheel opens. A press released
    /// sooner is a *tap* that passes through to the focused app, so the key keeps its
    /// normal function and other shortcuts. `0` opens the wheel immediately on press.
    var activationDelay: TimeInterval = 0.2
    /// Points the cursor must travel from the press point before the wheel opens.
    /// `0` disables drag-to-open (the wheel opens immediately / after `activationDelay`).
    /// When > 0 the wheel opens *only* on a drag this far, anchored at the press point;
    /// a release before then passes the trigger through. Replaces `activationDelay`
    /// as the gate while set.
    var activationDistance: CGFloat = 0
    /// Modifiers (a `CGEventFlags` mask) that must be held with the key for a `.key`
    /// trigger to fire — e.g. ⌘⇧ + Space. `0` means the bare key. Ignored for
    /// `.modifier` (the chord lives in `code`) and `.mouseButton`.
    var requiredModifiers: UInt64 = 0

    /// Device-dependent flag bits that distinguish left vs right modifier keys.
    /// `CGEventFlags.maskAlternate` (etc.) is set for *either* side; these bits
    /// pin the binding to one physical key. Values from IOKit's NX_DEVICE*KEYMASK.
    static let rightOptionMask: UInt64 = CGEventFlags.maskAlternate.rawValue | 0x0000_0040
    static let leftOptionMask: UInt64 = CGEventFlags.maskAlternate.rawValue | 0x0000_0020

    /// Standard, device-independent modifier masks, in display order (⌃⌥⇧⌘).
    static let chordModifiers: [(flag: CGEventFlags, glyph: String)] = [
        (.maskControl, "⌃"),
        (.maskAlternate, "⌥"),
        (.maskShift, "⇧"),
        (.maskCommand, "⌘"),
    ]

    /// Builds a device-independent chord mask (matches either physical side) from a
    /// set of standard modifier flags. Used by the Settings chord builder.
    static func chordMask(_ flags: [CGEventFlags]) -> UInt64 {
        flags.reduce(into: 0) { $0 |= $1.rawValue }
    }

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

    /// How the hold turns into an open. Drag distance takes precedence over the hold
    /// delay, which takes precedence over opening immediately. The single source of
    /// truth for the monitor's open-timing and event-swallowing decisions.
    enum ActivationMode { case immediate, holdDelay, drag }
    var activationMode: ActivationMode {
        if activationDistance > 0 { return .drag }
        return activationDelay <= 0 ? .immediate : .holdDelay
    }

    var displayName: String {
        switch kind {
        case .modifier:
            switch code {
            case Self.rightOptionMask: return "Right Option (⌥)"
            case Self.leftOptionMask: return "Left Option (⌥)"
            default:
                let glyphs = Self.modifierGlyphs(code)
                return glyphs.isEmpty ? "Modifier" : glyphs
            }
        case .key:
            return Self.modifierGlyphs(requiredModifiers) + KeyCodeFormatter.name(for: keyCode)
        case .mouseButton:
            // macOS button numbers are 0-based; the UI labels them 1-based (button
            // number 3 = "Mouse Button 4"), matching the SettingsView presets.
            return "Mouse Button \(code + 1)"
        }
    }

    /// Composes the modifier glyphs present in `mask` (⌃⌥⇧⌘ order). Empty if none.
    static func modifierGlyphs(_ mask: UInt64) -> String {
        chordModifiers.reduce(into: "") { result, modifier in
            if mask & modifier.flag.rawValue != 0 { result += modifier.glyph }
        }
    }
}

extension TriggerBinding {
    private enum CodingKeys: String, CodingKey {
        case kind, code, swallowEvent, activationDelay, activationDistance, requiredModifiers
    }

    // Custom decode (in an extension, to keep the synthesized memberwise init) so a
    // config.json predating `activationDelay`/`activationDistance` still decodes —
    // without it the whole Config would fail to decode and ConfigStore would reset
    // the user's settings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        code = try container.decode(UInt64.self, forKey: .code)
        swallowEvent = try container.decode(Bool.self, forKey: .swallowEvent)
        activationDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .activationDelay) ?? 0.2
        activationDistance = try container.decodeIfPresent(CGFloat.self, forKey: .activationDistance) ?? 0
        requiredModifiers = try container.decodeIfPresent(UInt64.self, forKey: .requiredModifiers) ?? 0
    }
}
