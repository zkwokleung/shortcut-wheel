import AppKit
import CoreGraphics
import Foundation
import os

/// Observes global input via a `CGEventTap` and reports hold of the configured
/// trigger as press/release callbacks. The tap is installed on the main run loop,
/// so its callback fires on the main thread; the class is `@MainActor` to match.
///
/// Requires Accessibility + Input Monitoring (see `PermissionsManager`). If those
/// aren't granted, `CGEvent.tapCreate` returns nil and `start()` reports failure.
@MainActor
final class GlobalHotkeyMonitor {
    private static let log = Logger(subsystem: "com.zkwokleung.shortcutwheel", category: "input")

    private(set) var binding: TriggerBinding

    /// Called on the main thread when the wheel should open. The `CGPoint` is the
    /// anchor (screen coords, y-up) to center the wheel on — the press point in
    /// drag-to-open mode, otherwise the current cursor.
    var onPress: ((CGPoint) -> Void)?
    var onRelease: (() -> Void)?
    /// Dismiss the wheel *without* selecting — used when the hold is ended by
    /// something other than a deliberate release (re-bind mid-hold, missed key-up).
    var onCancel: (() -> Void)?

    // `self` is handed to the C tap callback as an unretained pointer. It must
    // outlive the tap; AppDelegate owns this via a non-reassigned `lazy var` and
    // calls `stop()` on terminate, so the pointer is never dangling.
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isTriggerDown = false
    /// True once `onPress` has fired for the current hold (i.e. the wheel is shown).
    /// Distinguishes a deliberate hold from a quick tap that should pass through.
    private var wheelOpen = false
    /// The scheduled open for the current hold (hold-delay mode); cancelled if the
    /// trigger is released before the delay elapses.
    private var pendingOpen: DispatchWorkItem?
    /// Polls cursor distance in drag-to-open mode; nil unless a drag gate is armed.
    private var dragTimer: Timer?
    /// The swallowed `.down` of the current hold, kept so a press that turns out to
    /// be a tap (never opened the wheel) can be replayed to the focused app. nil
    /// unless a swallowing hold-delay/drag trigger is mid-press.
    private var bufferedDown: CGEvent?

    /// Tags replayed taps via `.eventSourceUserData` so the tap ignores its own
    /// re-injected events instead of matching them as a fresh trigger ("SW_RP").
    private static let replayMarker: Int64 = 0x53_57_5F_52_50
    /// True only while `replayBufferedTap` is posting. A mouse replay re-enters this
    /// tap; this is a marker-independent backstop so a re-injected event can never be
    /// re-buffered into an unbounded loop even if `.eventSourceUserData` were dropped.
    private var isReplaying = false

    private(set) var isRunning = false

    init(binding: TriggerBinding) {
        self.binding = binding
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: refcon
        ) else {
            Self.log.error("Failed to create event tap (permissions not granted?)")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Self.log.error("Failed to create run-loop source for event tap")
            CFMachPortInvalidate(tap)
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isRunning = true
        Self.log.info("Event tap started for trigger \(self.binding.displayName, privacy: .public)")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        eventTap = nil
        runLoopSource = nil
        cancelPendingOpen()
        cancelDragWatch()
        bufferedDown = nil
        isTriggerDown = false
        wheelOpen = false
        isRunning = false
    }

    func updateBinding(_ newBinding: TriggerBinding) {
        // If the trigger changes mid-hold, cancel the open wheel (don't fire the
        // highlighted slice — `onRelease` would dispatch its action).
        if isTriggerDown { onCancel?() }
        cancelPendingOpen()
        cancelDragWatch()
        bufferedDown = nil
        isTriggerDown = false
        wheelOpen = false
        binding = newBinding
    }

    // C trampoline: a CGEventTap callback is a bare function pointer and can't
    // capture context, so we round-trip `self` through the userInfo pointer. The
    // run loop guarantees this runs on main, so the actor hop is a safe assumption.
    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        return MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // A tap we replayed below (see `replayBufferedTap`); a mouse replay re-enters
        // this tap, so let it through to the app instead of matching it as a fresh
        // trigger and looping. The marker is primary; `isReplaying` is a backstop in
        // case `.eventSourceUserData` doesn't survive the HID round-trip.
        if isReplaying || event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return pass }

        // The system disables the tap if a callback is slow or on certain input;
        // re-enable it or it stays dead.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.log.notice("Event tap disabled (\(type.rawValue)); re-enabling")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        // Never swallow drag movement. A CGEventTap that discards an otherMouseDragged
        // event also discards the cursor movement it carries, freezing the pointer
        // while the trigger button is held — which breaks radial selection (the cursor
        // can't move to a slice) and drag-to-open (it needs the cursor to actually
        // travel). The button down/up are still swallowed below, so the app gets at
        // most orphaned drags with no matching button-down, which apps ignore.
        if type == .otherMouseDragged { return pass }

        guard let edge = triggerEdge(type: type, event: event) else { return pass }

        // Decide swallow/buffer/replay from `wheelOpen` as it stands *now*, before the
        // `.up` branch resets it — that's what tells a wheel-opening hold from a tap.
        let action = Self.swallowAction(
            swallow: binding.swallowEvent,
            kind: binding.kind,
            mode: binding.activationMode,
            edge: edge,
            wheelOpen: wheelOpen
        )

        switch edge {
        case .down:
            // Resync if a prior keyUp/mouseUp was missed (focus loss, fast switch):
            // cancel the stale hold (don't fire its selection) before opening fresh.
            if isTriggerDown { cancelPendingOpen(); cancelDragWatch(); bufferedDown = nil; onCancel?() }
            isTriggerDown = true
            wheelOpen = false
            // Hold the press back (copy: the live event is only valid for this call)
            // so it can be replayed if the hold turns out to be a tap.
            if action == .bufferAndSwallow { bufferedDown = event.copy() }
            switch binding.activationMode {
            case .drag:
                // Defer until the cursor leaves the press point by the configured
                // distance. A release before then is a tap that passes through.
                beginDragWatch()
            case .immediate:
                openWheel()
            case .holdDelay:
                // A tap (release before the delay) passes through untouched, so the
                // trigger keeps its normal function.
                scheduleOpen(after: binding.activationDelay)
            }
        case .up:
            cancelPendingOpen()
            cancelDragWatch()
            // Snapshot before resetting: `owned` says this release matches a press we
            // tracked; `wasOpen` says that press had opened the wheel.
            let owned = isTriggerDown
            let wasOpen = wheelOpen
            isTriggerDown = false
            wheelOpen = false
            if owned && wasOpen { onRelease?() }
            let disposition = Self.upDisposition(action: action, owned: owned, hasBuffer: bufferedDown != nil)
            if disposition == .replay {
                // Tap that never opened the wheel: replay the buffered press so the
                // focused app still gets its click/keystroke.
                replayBufferedTap(up: event)
            }
            bufferedDown = nil
            // Pass the release through whenever there's nothing to replay — an orphan
            // up (down never seen), a buffer cleared by a mid-hold rebind, or a
            // non-swallowing trigger — so the app never loses the release.
            switch disposition {
            case .pass: return pass
            case .swallow, .replay: return nil
            }
        case .repeatHold:
            // Auto-repeat fires only for a held key past the OS repeat delay — a hold,
            // never a tap — so it's swallowed (never buffered/replayed) whenever the
            // trigger hides its events, so a long hold delay can't leak a stream of
            // repeated keystrokes to the focused app.
            break
        }

        switch action {
        case .pass: return pass
        case .swallow, .bufferAndSwallow, .replayTapThenSwallow: return nil
        }
    }

    /// What the tap should do with a matched trigger event. Pure (value-typed) so the
    /// swallow/buffer/replay policy is unit-testable without a live `CGEvent`.
    ///
    /// Immediate mode consumes every matched event. Hold-delay/drag buffers the press
    /// and swallows it: a release while the wheel is open swallows too (the app sees
    /// neither edge); a release before it opened replays the buffered press as a tap.
    /// Non-swallowing triggers and modifiers always pass through unchanged.
    enum SwallowAction { case pass, swallow, bufferAndSwallow, replayTapThenSwallow }

    nonisolated static func swallowAction(
        swallow: Bool,
        kind: TriggerBinding.Kind,
        mode: TriggerBinding.ActivationMode,
        edge: Edge,
        wheelOpen: Bool
    ) -> SwallowAction {
        guard swallow, kind != .modifier else { return .pass }
        switch mode {
        case .immediate:
            return .swallow
        case .holdDelay, .drag:
            switch edge {
            case .down: return .bufferAndSwallow
            case .repeatHold: return .swallow
            case .up: return wheelOpen ? .swallow : .replayTapThenSwallow
            }
        }
    }

    /// How to handle a `.up` once the runtime facts are known: whether the release
    /// matched a press we tracked (`owned`) and whether a buffered press exists to
    /// replay (`hasBuffer`). A tap is only replayable when both hold — otherwise the
    /// release must pass through so the app never loses input (orphan up, or a buffer
    /// cleared by a mid-hold rebind). Pure so the policy is unit-testable.
    enum Disposition { case pass, swallow, replay }

    nonisolated static func upDisposition(action: SwallowAction, owned: Bool, hasBuffer: Bool) -> Disposition {
        switch action {
        case .pass: return .pass
        case .swallow, .bufferAndSwallow: return .swallow
        case .replayTapThenSwallow: return (owned && hasBuffer) ? .replay : .pass
        }
    }

    /// Re-injects the buffered press plus this release so a tap that never opened the
    /// wheel still reaches the app. The press is delivered as a click *on release*, so
    /// in-app press-and-hold gestures aren't preserved for a blocking trigger.
    ///
    /// Mouse goes to the HID tap so the window server routes the click to the app under
    /// the cursor; a key goes to the annotated session tap — downstream of ours, so it
    /// never re-enters, matching `KeySynthesizer` and avoiding stray hardware modifiers.
    /// Both are tagged with `replayMarker`, and `isReplaying` guards the mouse re-entry.
    private func replayBufferedTap(up: CGEvent) {
        guard let down = bufferedDown, let upCopy = up.copy() else { return }
        down.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        upCopy.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        let tap: CGEventTapLocation = binding.kind == .mouseButton ? .cghidEventTap : .cgAnnotatedSessionEventTap
        isReplaying = true
        down.post(tap: tap)
        upCopy.post(tap: tap)
        isReplaying = false
    }

    private func openWheel(at anchor: CGPoint? = nil) {
        pendingOpen = nil
        wheelOpen = true
        onPress?(anchor ?? NSEvent.mouseLocation)
    }

    private func scheduleOpen(after delay: TimeInterval) {
        cancelPendingOpen()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isTriggerDown, !self.wheelOpen else { return }
                self.openWheel()
            }
        }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    /// Opens the wheel once the cursor has moved `activationDistance` points from the
    /// press point, polling on the main run loop (trigger-agnostic; no mouse-move tap).
    private func beginDragWatch() {
        cancelDragWatch()
        let anchor = NSEvent.mouseLocation
        let distance = binding.activationDistance
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isTriggerDown, !self.wheelOpen else { return }
                let now = NSEvent.mouseLocation
                if hypot(now.x - anchor.x, now.y - anchor.y) >= distance {
                    self.cancelDragWatch()
                    self.openWheel(at: anchor)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer
    }

    private func cancelDragWatch() {
        dragTimer?.invalidate()
        dragTimer = nil
    }

    /// Whether a held modifier trigger should now be treated as released. A single
    /// (possibly device-specific) modifier releases as soon as its mask is no longer
    /// fully held. A multi-modifier chord (e.g. ⌃⌥) releases only once *every* one of
    /// its modifiers is up, so letting go of one doesn't commit the selection early.
    private func triggerReleased(currentFlags: CGEventFlags, isDown: Bool) -> Bool {
        let isChord = binding.flags.intersection(Self.standardModifiers).rawValue.nonzeroBitCount >= 2
        return isChord ? currentFlags.intersection(binding.flags).isEmpty : !isDown
    }

    /// Whether a key-down belongs to a `.key` trigger: the key code must match, and
    /// any required modifiers must be held *exactly* (the standard ⌃⌥⇧⌘ subset equals
    /// the requirement), so ⌘Space doesn't also fire on ⌃⌘Space. A bare key
    /// (`requiredModifiers == 0`) matches on key code alone, ignoring modifiers, so it
    /// behaves as it did before combos existed. Pure so it's unit-testable.
    nonisolated static func keyTriggerMatches(
        eventKeyCode: CGKeyCode,
        eventFlags: CGEventFlags,
        bindingKeyCode: CGKeyCode,
        requiredModifiers: UInt64
    ) -> Bool {
        guard eventKeyCode == bindingKeyCode else { return false }
        guard requiredModifiers != 0 else { return true }
        let required = CGEventFlags(rawValue: requiredModifiers).intersection(standardModifiers)
        return eventFlags.intersection(standardModifiers) == required
    }

    /// The device-independent modifier bits (⌃⌥⇧⌘). Used to compare held flags
    /// against a binding while ignoring device-side and non-coalesced bits.
    nonisolated static let standardModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    /// An event that belongs to the trigger and which edge it represents. `nil`
    /// for events unrelated to the trigger (pass them straight through).
    enum Edge { case down, up, repeatHold }

    private func triggerEdge(type: CGEventType, event: CGEvent) -> Edge? {
        switch binding.kind {
        case .modifier:
            guard type == .flagsChanged else { return nil }
            // `.contains` requires every bit of the binding mask — including the
            // device-dependent left/right bit — so right Option won't match left.
            let isDown = event.flags.contains(binding.flags)
            if isDown && !isTriggerDown { return .down }
            if isTriggerDown && triggerReleased(currentFlags: event.flags, isDown: isDown) {
                return .up
            }
            return nil

        case .key:
            let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            switch type {
            case .keyDown:
                guard Self.keyTriggerMatches(
                    eventKeyCode: keyCode,
                    eventFlags: event.flags,
                    bindingKeyCode: binding.keyCode,
                    requiredModifiers: binding.requiredModifiers
                ) else { return nil }
                return event.getIntegerValueField(.keyboardEventAutorepeat) == 0 ? .down : .repeatHold
            case .keyUp:
                // Release on the bound key always ends the hold, even if a required
                // modifier was lifted first, so the wheel can never stick open.
                return keyCode == binding.keyCode ? .up : nil
            default:
                return nil
            }

        case .mouseButton:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            guard button == binding.mouseButtonNumber else { return nil }
            switch type {
            case .otherMouseDown: return .down
            case .otherMouseUp: return .up
            default: return nil
            }
        }
    }
}
