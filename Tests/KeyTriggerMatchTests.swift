import CoreGraphics
import Testing
@testable import ShortcutWheel

/// `GlobalHotkeyMonitor.keyTriggerMatches` — the pure key-down match policy for `.key`
/// triggers, including required-modifier handling.
struct KeyTriggerMatchTests {
    private func matches(
        eventKeyCode: CGKeyCode,
        eventFlags: CGEventFlags = [],
        bindingKeyCode: CGKeyCode,
        requiredModifiers: CGEventFlags = []
    ) -> Bool {
        GlobalHotkeyMonitor.keyTriggerMatches(
            eventKeyCode: eventKeyCode,
            eventFlags: eventFlags,
            bindingKeyCode: bindingKeyCode,
            requiredModifiers: requiredModifiers.rawValue
        )
    }

    @Test func bareKeyMatchesOnKeyCodeAloneIgnoringModifiers() {
        #expect(matches(eventKeyCode: 49, bindingKeyCode: 49))
        // No required modifiers: held modifiers don't matter (unchanged legacy behavior).
        #expect(matches(eventKeyCode: 49, eventFlags: .maskCommand, bindingKeyCode: 49))
    }

    @Test func wrongKeyCodeNeverMatches() {
        #expect(!matches(eventKeyCode: 8, bindingKeyCode: 49))
        #expect(!matches(eventKeyCode: 8, eventFlags: .maskCommand, bindingKeyCode: 49, requiredModifiers: .maskCommand))
    }

    @Test func comboRequiresTheModifierHeld() {
        #expect(matches(eventKeyCode: 49, eventFlags: .maskCommand, bindingKeyCode: 49, requiredModifiers: .maskCommand))
        #expect(!matches(eventKeyCode: 49, bindingKeyCode: 49, requiredModifiers: .maskCommand))
    }

    @Test func comboRequiresExactModifierSet() {
        let cmdShift: CGEventFlags = [.maskCommand, .maskShift]
        #expect(matches(eventKeyCode: 49, eventFlags: cmdShift, bindingKeyCode: 49, requiredModifiers: cmdShift))
        // An extra held modifier must NOT match, so ⌘⇧Space != ⌃⌘⇧Space.
        #expect(!matches(eventKeyCode: 49, eventFlags: [.maskCommand, .maskShift, .maskControl], bindingKeyCode: 49, requiredModifiers: cmdShift))
        // A missing modifier must not match either.
        #expect(!matches(eventKeyCode: 49, eventFlags: .maskCommand, bindingKeyCode: 49, requiredModifiers: cmdShift))
    }

    @Test func deviceAndNonCoalescedBitsAreIgnored() {
        // Live key-down flags carry device-side and non-coalesced bits; only the
        // standard ⌃⌥⇧⌘ subset is compared.
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskNonCoalesced.rawValue | 0x08)
        #expect(matches(eventKeyCode: 49, eventFlags: flags, bindingKeyCode: 49, requiredModifiers: .maskCommand))
    }
}
