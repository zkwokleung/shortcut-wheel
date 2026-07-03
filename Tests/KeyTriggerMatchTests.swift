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

/// `GlobalHotkeyMonitor.keyEdge` — how a keyboard event maps to a trigger edge given a
/// fresh-press match and whether the hold is already owned.
struct KeyEdgeTests {
    private typealias Edge = GlobalHotkeyMonitor.Edge

    @Test func freshPressNeedsExactMatch() {
        #expect(GlobalHotkeyMonitor.keyEdge(isKeyDown: true, isAutorepeat: false, keyCodeMatches: true, freshMatch: true, heldDown: false) == .down)
        // Near-miss chord (right key code, wrong modifiers) is not our press.
        #expect(GlobalHotkeyMonitor.keyEdge(isKeyDown: true, isAutorepeat: false, keyCodeMatches: true, freshMatch: false, heldDown: false) == nil)
    }

    @Test func releaseIsSwallowedOnlyWhenOwned() {
        // Owned hold: the release ends it even after a modifier was lifted (freshMatch
        // would be false by then), so the wheel can't stick open.
        #expect(GlobalHotkeyMonitor.keyEdge(isKeyDown: false, isAutorepeat: false, keyCodeMatches: true, freshMatch: false, heldDown: true) == .up)
        // Near-miss press we passed through must NOT have its key-up swallowed —
        // otherwise the app gets a key-down with no matching key-up (stuck key).
        #expect(GlobalHotkeyMonitor.keyEdge(isKeyDown: false, isAutorepeat: false, keyCodeMatches: true, freshMatch: false, heldDown: false) == nil)
    }

    @Test func autorepeatFollowsOwnedHoldNotModifiers() {
        // Mid-hold repeat with the modifier since released (freshMatch false) is still
        // swallowed as repeatHold, so repeated keystrokes don't leak to the app.
        #expect(GlobalHotkeyMonitor.keyEdge(isKeyDown: true, isAutorepeat: true, keyCodeMatches: true, freshMatch: false, heldDown: true) == .repeatHold)
        // A repeat for a key we don't own passes through.
        #expect(GlobalHotkeyMonitor.keyEdge(isKeyDown: true, isAutorepeat: true, keyCodeMatches: true, freshMatch: false, heldDown: false) == nil)
    }

    @Test func differentKeyNeverMatchesReleaseOrRepeat() {
        #expect(GlobalHotkeyMonitor.keyEdge(isKeyDown: false, isAutorepeat: false, keyCodeMatches: false, freshMatch: false, heldDown: true) == nil)
        #expect(GlobalHotkeyMonitor.keyEdge(isKeyDown: true, isAutorepeat: true, keyCodeMatches: false, freshMatch: false, heldDown: true) == nil)
    }
}
