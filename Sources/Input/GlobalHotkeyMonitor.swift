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

        switch edge {
        case .down:
            // Resync if a prior keyUp/mouseUp was missed (focus loss, fast switch):
            // cancel the stale hold (don't fire its selection) before opening fresh.
            if isTriggerDown { cancelPendingOpen(); cancelDragWatch(); onCancel?() }
            isTriggerDown = true
            wheelOpen = false
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
            if isTriggerDown {
                isTriggerDown = false
                if wheelOpen {
                    wheelOpen = false
                    onRelease?()
                }
                // Otherwise it was a tap: the press already passed through; do nothing.
            }
        case .repeatHold:
            // Auto-repeat fires only for a held key (past the OS repeat delay) — it is
            // a hold, never a tap — so swallow repeats whenever the trigger hides its
            // events, even before the wheel opens, so a long hold delay can't leak a
            // stream of repeated keystrokes to the focused app.
            return binding.swallowEvent ? nil : pass
        }

        return shouldSwallow ? nil : pass
    }

    /// Whether to consume the current matched trigger event. In immediate mode all
    /// matched key/mouse events are swallowed uniformly (no auto-repeat leaks). In
    /// hold-delay mode the press/release pass through (so taps work and down/up stay
    /// balanced) and only auto-repeat is swallowed, once the wheel is open.
    private var shouldSwallow: Bool {
        guard binding.swallowEvent, binding.kind != .modifier else { return false }
        // Immediate mode swallows every matched event. Hold-delay and drag-to-open let
        // taps pass through, swallowing only once the wheel is open; `.up` clears
        // wheelOpen before this check, so a release always passes through (down/up
        // stay balanced).
        switch binding.activationMode {
        case .immediate: return true
        case .holdDelay, .drag: return wheelOpen
        }
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
        let standard: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        let isChord = binding.flags.intersection(standard).rawValue.nonzeroBitCount >= 2
        return isChord ? currentFlags.intersection(binding.flags).isEmpty : !isDown
    }

    /// An event that belongs to the trigger and which edge it represents. `nil`
    /// for events unrelated to the trigger (pass them straight through).
    private enum Edge { case down, up, repeatHold }

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
            guard keyCode == binding.keyCode else { return nil }
            switch type {
            case .keyDown:
                return event.getIntegerValueField(.keyboardEventAutorepeat) == 0 ? .down : .repeatHold
            case .keyUp:
                return .up
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
