import AppKit
import Combine
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.zkwokleung.shortcutwheel", category: "app")

    private lazy var config = ConfigStore.shared
    private let overlay = OverlayWindowController()
    private let dispatcher = ActionDispatcher()
    private lazy var hotkeyMonitor = GlobalHotkeyMonitor(binding: config.trigger)
    private var triggerObserver: AnyCancellable?
    private var permissionObserver: AnyCancellable?

    private var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Under `xcodebuild test` the app is the test host; don't install the event
        // tap or prompt for permissions during a unit-test run.
        guard !isRunningTests else { return }

        let permissions = PermissionsManager.shared
        permissions.refresh()
        permissions.startMonitoring()
        permissions.requestIfNeeded()

        overlay.wheelProvider = { [weak self] id in self?.config.wheel(id: id) }

        // Re-bind the monitor when the trigger is changed in Settings.
        triggerObserver = config.$config
            .map(\.trigger)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] newTrigger in self?.hotkeyMonitor.updateBinding(newTrigger) }

        hotkeyMonitor.onPress = { [weak self] anchor in
            guard let self, let root = self.config.rootWheel else { return }
            self.overlay.show(rootWheel: root, at: anchor)
        }
        hotkeyMonitor.onRelease = { [weak self] in
            guard let self else { return }
            guard let slice = self.overlay.hide() else {
                Self.log.info("Wheel cancelled")
                return
            }
            self.handle(slice)
        }
        hotkeyMonitor.onCancel = { [weak self] in
            self?.overlay.hide() // dismiss without dispatching a selection
        }

        if !hotkeyMonitor.start() {
            Self.log.error("Hotkey monitor failed to start; grant Accessibility + Input Monitoring")
        }

        // The event tap can't be created until permissions are granted. If start()
        // failed at launch, retry once the user grants them — no relaunch needed.
        permissionObserver = Publishers.CombineLatest(
            permissions.$accessibilityGranted,
            permissions.$inputMonitoringGranted
        )
        .sink { [weak self] accessibility, inputMonitoring in
            guard let self, accessibility, inputMonitoring, !self.hotkeyMonitor.isRunning else { return }
            if self.hotkeyMonitor.start() {
                Self.log.info("Event tap started after permissions were granted")
            }
        }
    }

    private func handle(_ slice: WheelSlice) {
        switch dispatcher.perform(slice.action) {
        case .done:
            Self.log.info("Performed: \(slice.label, privacy: .public)")
        case .openSubWheel:
            // Sub-wheels are entered by dwelling during the hold, not on release —
            // a release on an un-entered sub-wheel slice is a no-op.
            break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor.stop()
        // Flush any edit still inside the autosave debounce window.
        config.save()
    }
}
