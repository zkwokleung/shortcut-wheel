import SwiftUI

@main
struct ShortcutWheelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var permissions = PermissionsManager.shared
    @StateObject private var updates = UpdateChecker.shared

    var body: some Scene {
        MenuBarExtra("ShortcutWheel", image: "MenuBarIcon") {
            MenuContent(permissions: permissions, updates: updates)
        }

        Settings {
            SettingsView(config: ConfigStore.shared, permissions: permissions)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var updates: UpdateChecker
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !permissions.allGranted {
            Text(permissions.statusSummary)
            Button("Grant Permissions…") { permissions.requestIfNeeded() }
            Button("Open Privacy Settings…") { permissions.openAccessibilitySettings() }
            Divider()
        }

        if case .available(let release) = updates.state {
            Text("Update available — \(release.version)")
            Button("Download…") { updates.openDownload(release) }
            Divider()
        }

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Check for Updates…") {
            Task {
                await updates.check(userInitiated: true)
                presentResult(updates.state)
            }
        }

        Divider()

        Button("Quit ShortcutWheel") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private func presentResult(_ state: UpdateChecker.State) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        switch state {
        case .available(let release):
            alert.messageText = "Update available"
            alert.informativeText = "ShortcutWheel \(release.version) is available. You have \(updates.currentVersion)."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                updates.openDownload(release)
            }
        case .upToDate:
            alert.messageText = "You’re up to date"
            alert.informativeText = "ShortcutWheel \(updates.currentVersion) is the latest version."
            alert.runModal()
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t check for updates"
            alert.informativeText = message
            alert.runModal()
        case .idle, .checking:
            break
        }
    }
}
