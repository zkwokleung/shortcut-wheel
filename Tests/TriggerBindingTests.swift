import CoreGraphics
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

    @Test func keyCodeTruncates() {
        let binding = TriggerBinding(kind: .key, code: 8, swallowEvent: false)
        #expect(binding.keyCode == 8)
    }
}
