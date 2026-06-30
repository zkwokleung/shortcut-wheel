import CoreGraphics
import Dispatch

/// Synthesizes a key chord into the focused app. Because the overlay panel is
/// non-activating, focus never left the user's app, so posted events land there.
/// Requires Accessibility permission (already needed for the event tap).
///
/// Targets shortcut chords (⌘/⌃/⌥/⇧ + key), NOT literal text entry — shifted
/// *characters* (e.g. typing `!`) aren't guaranteed across apps.
enum KeySynthesizer {
    private static let deviceIndependentModifiers: CGEventFlags =
        [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    /// Max time to wait for a held trigger modifier to clear before posting anyway.
    private static let maxWaitAttempts = 15 // × 10ms ≈ 150ms
    private static let pollInterval: DispatchTimeInterval = .milliseconds(10)

    static func post(_ combo: KeyCombo) {
        postWhenModifiersSettled(combo, attemptsLeft: maxWaitAttempts)
    }

    /// The trigger may be a held modifier (e.g. right-Option); the window server
    /// OR's live hardware modifier flags into posted events, so a still-held Option
    /// would corrupt the chord (⌘C → ⌥⌘C). Wait until no modifier beyond the
    /// chord's own is live, then post — rather than guessing a fixed delay.
    private static func postWhenModifiersSettled(_ combo: KeyCombo, attemptsLeft: Int) {
        let live = CGEventSource.flagsState(.combinedSessionState)
        let stray = live.intersection(deviceIndependentModifiers).subtracting(combo.flags)

        guard stray.isEmpty || attemptsLeft <= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
                postWhenModifiersSettled(combo, attemptsLeft: attemptsLeft - 1)
            }
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false)
        else { return }

        keyDown.flags = combo.flags
        keyUp.flags = combo.flags

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
