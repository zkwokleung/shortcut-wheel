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

    var emptySlotCount: Int { slices.lazy.filter { $0 == nil }.count }

    /// Shrinks the wheel by `count` slots, dropping empty slots before filled ones so
    /// assigned shortcuts survive when possible. Empties are removed from the end
    /// first; once they run out, filled slots are removed from the end. Surviving
    /// filled slots shift to lower positions as gaps close.
    mutating func removeSlots(_ count: Int) {
        var remaining = min(max(count, 0), slices.count)
        var index = slices.count - 1
        while remaining > 0 && index >= 0 {
            if slices[index] == nil {
                slices.remove(at: index)
                remaining -= 1
            }
            index -= 1
        }
        if remaining > 0 { slices.removeLast(remaining) }
    }
}

/// How the wheel maps the cursor to a slice. `direction` selects the nearest slice
/// by angle at any distance past the dead zone (flick-style); `precisePosition`
/// also requires the cursor to be within the wheel's outer radius, so a cursor off
/// the wheel selects nothing.
enum SelectionMode: String, Codable, CaseIterable, Identifiable {
    case direction
    case precisePosition

    var id: String { rawValue }

    var label: String {
        switch self {
        case .direction: return "Direction"
        case .precisePosition: return "Precise Position"
        }
    }

    var detail: String {
        switch self {
        case .direction: return "Aim toward a slice from anywhere past the center — flick-style."
        case .precisePosition: return "Select only when the cursor is on the wedge; off the wheel selects nothing."
        }
    }
}

/// The persisted document: schema version, every wheel, the active trigger, and
/// which wheel opens on press.
struct Config: Codable, Equatable {
    static let currentSchemaVersion = 1

    var version: Int
    var wheels: [Wheel]
    var trigger: TriggerBinding
    var rootWheelID: UUID
    var selectionMode: SelectionMode = .direction

    init(version: Int, wheels: [Wheel], trigger: TriggerBinding, rootWheelID: UUID,
         selectionMode: SelectionMode = .direction) {
        self.version = version
        self.wheels = wheels
        self.trigger = trigger
        self.rootWheelID = rootWheelID
        self.selectionMode = selectionMode
    }

    // Custom decode so a config written before `selectionMode` existed still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        wheels = try c.decode([Wheel].self, forKey: .wheels)
        trigger = try c.decode(TriggerBinding.self, forKey: .trigger)
        rootWheelID = try c.decode(UUID.self, forKey: .rootWheelID)
        selectionMode = try c.decodeIfPresent(SelectionMode.self, forKey: .selectionMode) ?? .direction
    }
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
