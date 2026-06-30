import SwiftUI

enum SettingsSection: Hashable {
    case permissions
    case trigger
    case wheel(UUID)
}

struct SettingsView: View {
    @ObservedObject var config: ConfigStore
    @ObservedObject var permissions: PermissionsManager
    @State private var selection: SettingsSection? = .permissions

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("App") {
                Label("Permissions", systemImage: "lock.shield").tag(SettingsSection.permissions)
                Label("Trigger", systemImage: "hand.tap").tag(SettingsSection.trigger)
            }
            Section("Wheels") {
                ForEach(config.config.wheels) { wheel in
                    Label(wheel.name, systemImage: wheel.id == config.config.rootWheelID ? "smallcircle.filled.circle" : "circle")
                        .tag(SettingsSection.wheel(wheel.id))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: addWheel) { Image(systemName: "plus") }
                Button(action: deleteSelectedWheel) { Image(systemName: "minus") }
                    .disabled(!canDeleteSelection)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .permissions, nil:
            PermissionsSection(permissions: permissions)
        case .trigger:
            TriggerSection(trigger: $config.config.trigger)
        case .wheel(let id):
            if let binding = wheelBinding(id) {
                WheelEditorView(
                    wheel: binding,
                    isRoot: id == config.config.rootWheelID,
                    otherWheels: config.config.wheels.filter { $0.id != id },
                    makeRoot: { config.config.rootWheelID = id }
                )
            } else {
                ContentUnavailableView("Wheel not found", systemImage: "questionmark.circle")
            }
        }
    }

    /// Binds by id (not a frozen index) so a concurrent delete/reorder can't make
    /// the setter write to the wrong wheel or out of bounds.
    private func wheelBinding(_ id: UUID) -> Binding<Wheel>? {
        guard let current = config.config.wheels.first(where: { $0.id == id }) else { return nil }
        let store = config
        return Binding(
            get: { store.config.wheels.first { $0.id == id } ?? current },
            set: { newValue in
                if let index = store.config.wheels.firstIndex(where: { $0.id == id }) {
                    store.config.wheels[index] = newValue
                }
            }
        )
    }

    private var canDeleteSelection: Bool {
        guard case .wheel(let id) = selection else { return false }
        // Never delete the root wheel or the last remaining wheel.
        return id != config.config.rootWheelID && config.config.wheels.count > 1
    }

    private func addWheel() {
        // Start with four empty slots; the editor's picker can grow it (4/6/8/12).
        let wheel = Wheel(name: "New Wheel", slices: Array(repeating: nil, count: 4))
        config.config.wheels.append(wheel)
        selection = .wheel(wheel.id)
    }

    private func deleteSelectedWheel() {
        guard case .wheel(let id) = selection, canDeleteSelection else { return }
        config.config.wheels.removeAll { $0.id == id }
        // Drop any sub-wheel references to the deleted wheel (skipping empty slots).
        for w in config.config.wheels.indices {
            for s in config.config.wheels[w].slices.indices
            where config.config.wheels[w].slices[s]?.action.subWheelID == id {
                config.config.wheels[w].slices[s]?.action = .none
            }
        }
        selection = .permissions
    }
}

private struct PermissionsSection: View {
    @ObservedObject var permissions: PermissionsManager

    var body: some View {
        Form {
            Section("Permissions") {
                row("Accessibility", granted: permissions.accessibilityGranted,
                    open: permissions.openAccessibilitySettings)
                row("Input Monitoring", granted: permissions.inputMonitoringGranted,
                    open: permissions.openInputMonitoringSettings)
                Button("Request Permissions") { permissions.requestIfNeeded() }
            }
            Section {
                Text("ShortcutWheel needs Accessibility to send keystrokes and Input Monitoring to detect the global trigger.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Permissions")
    }

    private func row(_ name: String, granted: Bool, open: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(name)
            Spacer()
            Button("Open Settings…", action: open)
        }
    }
}

private struct TriggerSection: View {
    @Binding var trigger: TriggerBinding

    private static let presets: [(name: String, binding: TriggerBinding)] = [
        ("Right Option (⌥)", TriggerBinding(kind: .modifier, code: TriggerBinding.rightOptionMask, swallowEvent: false)),
        ("Left Option (⌥)", TriggerBinding(kind: .modifier, code: TriggerBinding.leftOptionMask, swallowEvent: false)),
        ("Control (⌃)", TriggerBinding(kind: .modifier, code: CGEventFlags.maskControl.rawValue, swallowEvent: false)),
        ("Mouse Button 4", TriggerBinding(kind: .mouseButton, code: 3, swallowEvent: true)),
        ("Mouse Button 5", TriggerBinding(kind: .mouseButton, code: 4, swallowEvent: true)),
    ]

    var body: some View {
        Form {
            Section("Trigger") {
                Picker("Hold to open", selection: presetSelection) {
                    ForEach(Self.presets.indices, id: \.self) { i in
                        Text(Self.presets[i].name).tag(i as Int?)
                    }
                    if presetSelection.wrappedValue == nil {
                        Text("Custom (\(trigger.displayName))").tag(nil as Int?)
                    }
                }
                Toggle("Hide trigger from other apps", isOn: $trigger.swallowEvent)
                    .help("Consume the trigger event so it doesn't reach the focused app. Not applied to modifier keys.")
            }
            Section {
                Text("Current: \(trigger.displayName)").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Trigger")
    }

    private var presetSelection: Binding<Int?> {
        Binding(
            get: { Self.presets.firstIndex { $0.binding.kind == trigger.kind && $0.binding.code == trigger.code } },
            set: { if let i = $0 { trigger = Self.presets[i].binding } }
        )
    }
}
