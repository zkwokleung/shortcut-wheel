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

    /// Called on the main thread when the trigger is first pressed / released.
    var onPress: (() -> Void)?
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
        isTriggerDown = false
        isRunning = false
    }

    func updateBinding(_ newBinding: TriggerBinding) {
        // If the trigger changes mid-hold, cancel the open wheel (don't fire the
        // highlighted slice — `onRelease` would dispatch its action).
        if isTriggerDown { onCancel?() }
        isTriggerDown = false
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

        // While a swallowing mouse-button trigger is held, also consume drags so the
        // focused app doesn't receive orphaned drag events with no matching down.
        if type == .otherMouseDragged {
            let swallowDrag = isTriggerDown && binding.kind == .mouseButton && binding.swallowEvent
            return swallowDrag ? nil : pass
        }

        guard let edge = triggerEdge(type: type, event: event) else { return pass }

        switch edge {
        case .down:
            // Resync if a prior keyUp/mouseUp was missed (focus loss, fast switch):
            // cancel the stale hold (don't fire its selection) before opening fresh.
            if isTriggerDown { onCancel?() }
            isTriggerDown = true
            onPress?()
        case .up:
            if isTriggerDown {
                isTriggerDown = false
                onRelease?()
            }
        case .repeatHold:
            break
        }

        // All matched trigger events (down/up/repeat) are swallowed uniformly when
        // configured, so a held key never leaks auto-repeats to the focused app.
        // Modifiers are never swallowed — that would break the modifier globally.
        let swallow = binding.swallowEvent && binding.kind != .modifier
        return swallow ? nil : pass
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
            if !isDown && isTriggerDown { return .up }
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
