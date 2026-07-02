import CoreGraphics
import Foundation
import Testing
@testable import ShortcutWheel

struct TriggerBindingTests {
    @Test func rightOptionRequiresDeviceBit() {
        let binding = TriggerBinding.rightOption
        #expect(binding.kind == .modifier)
        // Must carry both the generic Option mask and the right-side device bit,
        // so it won't match left Option.
        #expect(binding.flags.contains(.maskAlternate))
        #expect(binding.code == TriggerBinding.rightOptionMask)
        #expect(binding.displayName == "Right Option (⌥)")
    }

    @Test func mouseButtonNumberRoundTrips() {
        let binding = TriggerBinding(kind: .mouseButton, code: 3, swallowEvent: true)
        #expect(binding.mouseButtonNumber == 3)
    }

    @Test func mouseButtonNumberNeverNegative() {
        // A malformed/high-bit code must clamp, not become a negative Int64.
        let binding = TriggerBinding(kind: .mouseButton, code: .max, swallowEvent: true)
        #expect(binding.mouseButtonNumber >= 0)
    }

    @Test func mouseButtonDisplayNameMatchesPresetLabels() {
        // Preset "Mouse Button 4" stores code 3; the label must agree.
        #expect(TriggerBinding(kind: .mouseButton, code: 3, swallowEvent: true).displayName == "Mouse Button 4")
        #expect(TriggerBinding(kind: .mouseButton, code: 4, swallowEvent: true).displayName == "Mouse Button 5")
    }

    @Test func middleButtonIsButtonNumberTwo() {
        // The "Middle Click" preset stores code 2 (macOS middle button), shown 1-based.
        let middle = TriggerBinding(kind: .mouseButton, code: 2, swallowEvent: true)
        #expect(middle.mouseButtonNumber == 2)
        #expect(middle.displayName == "Mouse Button 3")
    }

    @Test func keyCodeTruncates() {
        let binding = TriggerBinding(kind: .key, code: 8, swallowEvent: false)
        #expect(binding.keyCode == 8)
    }

    @Test func legacyConfigDecodesWithDefaultDelay() throws {
        // A pre-`activationDelay` config has no such key; it must decode (not throw,
        // which would make ConfigStore reset the user's settings) with the default.
        let json = #"{"kind":"modifier","code":524288,"swallowEvent":false}"#
        let binding = try JSONDecoder().decode(TriggerBinding.self, from: Data(json.utf8))
        #expect(binding.activationDelay == 0.2)
        #expect(binding.kind == .modifier)
    }

    @Test func activationDelayRoundTrips() throws {
        let binding = TriggerBinding(kind: .modifier, code: 524288, swallowEvent: false, activationDelay: 0.35)
        let decoded = try JSONDecoder().decode(TriggerBinding.self, from: JSONEncoder().encode(binding))
        #expect(decoded == binding)
        #expect(decoded.activationDelay == 0.35)
    }

    @Test func legacyConfigDecodesWithDefaultDistance() throws {
        // A config predating `activationDistance` must decode with the default (0 =
        // drag-to-open disabled), not throw and wipe the user's settings.
        let json = #"{"kind":"mouseButton","code":2,"swallowEvent":true,"activationDelay":0.2}"#
        let binding = try JSONDecoder().decode(TriggerBinding.self, from: Data(json.utf8))
        #expect(binding.activationDistance == 0)
        #expect(binding.kind == .mouseButton)
    }

    @Test func activationDistanceRoundTrips() throws {
        let binding = TriggerBinding(kind: .mouseButton, code: 2, swallowEvent: true, activationDistance: 40)
        let decoded = try JSONDecoder().decode(TriggerBinding.self, from: JSONEncoder().encode(binding))
        #expect(decoded == binding)
        #expect(decoded.activationDistance == 40)
    }

    @Test func keyDisplayNameUsesSpecialKeyName() {
        // Space (keycode 49) is in the special-key table, so it's layout-independent.
        let binding = TriggerBinding(kind: .key, code: 49, swallowEvent: false)
        #expect(binding.displayName == "Space")
    }

    @Test func keyDisplayNamePrefixesRequiredModifiers() {
        var binding = TriggerBinding(kind: .key, code: 49, swallowEvent: false)
        binding.requiredModifiers = TriggerBinding.chordMask([.maskCommand, .maskShift])
        #expect(binding.displayName == "⇧⌘Space") // glyphs render in ⌃⌥⇧⌘ order
    }

    @Test func legacyConfigDecodesWithoutRequiredModifiers() throws {
        // A config predating `requiredModifiers` must decode with the default (0 = bare
        // key), not throw and wipe the user's settings.
        let json = #"{"kind":"key","code":49,"swallowEvent":false,"activationDelay":0.2}"#
        let binding = try JSONDecoder().decode(TriggerBinding.self, from: Data(json.utf8))
        #expect(binding.requiredModifiers == 0)
        #expect(binding.kind == .key)
    }

    @Test func requiredModifiersRoundTrip() throws {
        var binding = TriggerBinding(kind: .key, code: 49, swallowEvent: true)
        binding.requiredModifiers = TriggerBinding.chordMask([.maskCommand, .maskShift])
        let decoded = try JSONDecoder().decode(TriggerBinding.self, from: JSONEncoder().encode(binding))
        #expect(decoded == binding)
        #expect(decoded.requiredModifiers == binding.requiredModifiers)
    }

    @Test func chordDisplayNameComposesGlyphs() {
        let code = TriggerBinding.chordMask([.maskControl, .maskAlternate])
        let binding = TriggerBinding(kind: .modifier, code: code, swallowEvent: false)
        #expect(binding.displayName == "⌃⌥")
    }

    @Test func chordMaskMatchesWhenAllModifiersHeld() {
        let chord = TriggerBinding(kind: .modifier, code: TriggerBinding.chordMask([.maskControl, .maskAlternate]), swallowEvent: false)
        // Live flags holding ⌃⌥ (plus unrelated bits) contain the chord; ⌃ alone does not.
        let bothHeld = CGEventFlags(rawValue: chord.code | CGEventFlags.maskNonCoalesced.rawValue)
        let controlOnly = CGEventFlags.maskControl
        #expect(bothHeld.contains(chord.flags))
        #expect(!controlOnly.contains(chord.flags))
    }
}
