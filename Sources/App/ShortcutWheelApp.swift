import SwiftUI

@main
struct ShortcutWheelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var permissions = PermissionsManager.shared

    var body: some Scene {
        MenuBarExtra("ShortcutWheel", systemImage: "circle.grid.cross.fill") {
            MenuContent(permissions: permissions)
        }

        Settings {
            SettingsView(config: ConfigStore.shared, permissions: permissions)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var permissions: PermissionsManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !permissions.allGranted {
            Text(permissions.statusSummary)
            Button("Grant Permissions…") { permissions.requestIfNeeded() }
            Button("Open Privacy Settings…") { permissions.openAccessibilitySettings() }
            Divider()
        }

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit ShortcutWheel") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
