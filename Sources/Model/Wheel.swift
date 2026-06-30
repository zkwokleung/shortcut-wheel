import CoreGraphics
import SwiftUI

/// What a slice does when selected. `Codable` is synthesized for the associated
/// values; the JSON tags each case by name. NOTE: renaming a case breaks decoding
/// of existing config files — bump `Config.currentSchemaVersion` and migrate.
enum Action: Codable, Equatable {
    case sendKeys(KeyCombo)
    case openURL(String)
    case openApp(path: String)
    case runScript(String)
    case subWheel(wheelID: UUID)
    case openSettings
    case none

    var isSubWheel: Bool {
        if case .subWheel = self { return true }
        return false
    }

    var subWheelID: UUID? {
        if case .subWheel(let id) = self { return id }
        return nil
    }
}

/// A key chord to synthesize. `keyCode` is a virtual key (CGKeyCode); `modifiers`
/// is a raw `CGEventFlags` mask (e.g. `maskCommand`). Targets shortcut chords, not
/// literal text entry.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64

    init(keyCode: UInt16, modifiers: CGEventFlags = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
    }

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }
}

/// One wedge of a wheel. Named `WheelSlice` (not `Slice`) to avoid shadowing the
/// standard library's `Slice<Base>`, which is the type of array/collection subscripts.
struct WheelSlice: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var symbol: String?
    /// `#RRGGBB`. Stored as a string so the model stays portable/serializable.
    var tintHex: String = "#5B8DEF"
    var action: Action
}

struct Wheel: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Fixed slots: `slices.count` is the slot count, element index is the angular
    /// position (0 = top, clockwise), and `nil` is an empty slot. A legacy config
    /// (plain array of objects) decodes as all-filled slots.
    var slices: [WheelSlice?]
}

/// The persisted document: schema version, every wheel, the active trigger, and
/// which wheel opens on press.
struct Config: Codable, Equatable {
    static let currentSchemaVersion = 1

    var version: Int
    var wheels: [Wheel]
    var trigger: TriggerBinding
    var rootWheelID: UUID
}

extension Color {
    /// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA` (with or without `#`, whitespace
    /// tolerated). Falls back to gray on malformed input.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        // Expand shorthand #RGB → #RRGGBB.
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }

        guard (cleaned.count == 6 || cleaned.count == 8),
              cleaned.allSatisfy(\.isHexDigit),
              let value = UInt32(cleaned, radix: 16) else {
            self = .gray
            return
        }

        let hasAlpha = cleaned.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
