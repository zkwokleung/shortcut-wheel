import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

/// A click-to-record shortcut field. While armed, a local event monitor captures the
/// next key press (with any held ⌘⌥⌃⇧) and reports it as `(keyCode, flags)`; the
/// event is swallowed so it never reaches the focused control. Esc cancels. When an
/// `onClear` is provided, ⌫/⌦ clears instead of recording (so those keys stay bindable
/// when it isn't). Modifier-only presses are ignored — it waits for a real key.
struct ShortcutRecorderField: View {
    let label: String
    /// Shown when idle; `nil` renders a "click to record" placeholder.
    let display: String?
    let onRecord: (CGKeyCode, CGEventFlags) -> Void
    var onClear: (() -> Void)?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button(action: toggle) {
                Text(buttonTitle).frame(minWidth: 150)
            }
            .help("Click, then press the key you want, holding any modifiers.")
            if onClear != nil, !isRecording, display != nil {
                Button { onClear?() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Clear")
            }
        }
        .onDisappear(perform: stop)
    }

    private var buttonTitle: String {
        if isRecording { return "Press shortcut… (Esc to cancel)" }
        return display ?? "Click to Record"
    }

    private func toggle() { isRecording ? stop() : start() }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    /// Returns nil to swallow the event while armed (so it doesn't beep, type, or
    /// trigger a control); the captured key is reported via `onRecord`/`onClear`.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        guard event.type == .keyDown else { return nil } // ignore flagsChanged; wait for a key
        let keyCode = CGKeyCode(event.keyCode)
        defer { stop() }
        if Int(keyCode) == kVK_Escape { return nil }
        let isDelete = Int(keyCode) == kVK_Delete || Int(keyCode) == kVK_ForwardDelete
        if let onClear, isDelete {
            onClear()
        } else {
            onRecord(keyCode, event.modifierFlags.cgEventFlags)
        }
        return nil
    }
}

private extension NSEvent.ModifierFlags {
    /// The standard ⌃⌥⇧⌘ subset as a device-independent `CGEventFlags` mask.
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}
