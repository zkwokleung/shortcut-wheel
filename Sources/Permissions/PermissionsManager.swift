import AppKit
import ApplicationServices
import IOKit.hid

/// Tracks the two TCC permissions ShortcutWheel needs to observe global input
/// and synthesize keystrokes: Accessibility and Input Monitoring. Neither is
/// entitlement-gated; both are granted by the user in System Settings, so we
/// poll their live state and surface it in the UI.
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var inputMonitoringGranted = false

    private var pollTimer: Timer?

    var allGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    var statusSummary: String {
        switch (accessibilityGranted, inputMonitoringGranted) {
        case (true, true): return "All permissions granted"
        case (false, false): return "Accessibility & Input Monitoring needed"
        case (false, true): return "Accessibility permission needed"
        case (true, false): return "Input Monitoring permission needed"
        }
    }

    private init() {
        refresh()
    }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Poll while the user is in the granting flow so the menu/Settings reflect
    /// changes made in System Settings without needing an app relaunch.
    func startMonitoring() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func requestIfNeeded() {
        if !accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if !inputMonitoringGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
