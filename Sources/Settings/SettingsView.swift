import SwiftUI

enum SettingsSection: Hashable {
    case permissions
    case trigger
    case selectionMode
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
                Label("Selection", systemImage: "scope").tag(SettingsSection.selectionMode)
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
        case .selectionMode:
            SelectionModeSection(mode: $config.config.selectionMode)
        case .wheel(let id):
            if let binding = wheelBinding(id) {
                WheelEditorView(
                    wheel: binding,
                    isRoot: id == config.config.rootWheelID,
                    otherWheels: config.config.wheels.filter { $0.id != id },
                    selectionMode: config.config.selectionMode,
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

private struct SelectionModeSection: View {
    @Binding var mode: SelectionMode

    var body: some View {
        Form {
            Section("Selection") {
                Picker("How the wheel selects", selection: $mode) {
                    ForEach(SelectionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
            Section {
                Text(mode.detail)
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Selection")
    }
}

private struct TriggerSection: View {
    @Binding var trigger: TriggerBinding

    private static let presets: [(name: String, binding: TriggerBinding)] = [
        ("Right Option (⌥)", TriggerBinding(kind: .modifier, code: TriggerBinding.rightOptionMask, swallowEvent: false)),
        ("Left Option (⌥)", TriggerBinding(kind: .modifier, code: TriggerBinding.leftOptionMask, swallowEvent: false)),
        ("Control (⌃)", TriggerBinding(kind: .modifier, code: CGEventFlags.maskControl.rawValue, swallowEvent: false)),
        ("Control + Option (⌃⌥)", TriggerBinding(kind: .modifier, code: TriggerBinding.chordMask([.maskControl, .maskAlternate]), swallowEvent: false)),
        ("Option + Command (⌥⌘)", TriggerBinding(kind: .modifier, code: TriggerBinding.chordMask([.maskAlternate, .maskCommand]), swallowEvent: false)),
        ("Middle Click (Mouse 3)", TriggerBinding(kind: .mouseButton, code: 2, swallowEvent: true)),
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
                if trigger.kind == .modifier {
                    chordBuilder
                }
            }

            Section("Custom Key") {
                ShortcutRecorderField(
                    label: "Keyboard shortcut",
                    display: trigger.kind == .key ? trigger.displayName : nil,
                    onRecord: { keyCode, flags in
                        // Preserve the user's activation tuning + swallow choice, like
                        // switching presets does.
                        trigger = TriggerBinding(
                            kind: .key,
                            code: UInt64(keyCode),
                            swallowEvent: trigger.swallowEvent,
                            activationDelay: trigger.activationDelay,
                            activationDistance: trigger.activationDistance,
                            requiredModifiers: flags.rawValue
                        )
                    }
                )
                Text("Optionally hold ⌃⌥⇧⌘ while recording.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Drag to Open") {
                Slider(value: $trigger.activationDistance, in: 0...200, step: 5) {
                    Text("Drag distance")
                } minimumValueLabel: {
                    Text("Off")
                } maximumValueLabel: {
                    Text("200")
                }
                HStack {
                    Text("Open after dragging").foregroundStyle(.secondary)
                    Spacer()
                    Text(distanceLabel).monospacedDigit()
                }
                Text("Require dragging the cursor this far before the wheel opens; it appears at the press point so the drag aims a slice. A press without dragging passes through. Replaces the hold delay while set.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hold Delay") {
                Slider(value: $trigger.activationDelay, in: 0...0.5, step: 0.05) {
                    Text("Hold delay")
                } minimumValueLabel: {
                    Text("Off")
                } maximumValueLabel: {
                    Text("0.5s")
                }
                .disabled(trigger.activationDistance > 0)
                HStack {
                    Text("Open after").foregroundStyle(.secondary)
                    Spacer()
                    Text(delayLabel).monospacedDigit()
                }
                Text("A quick tap passes through to the focused app, so the trigger keeps its normal function. Hold past the delay to open the wheel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(trigger.activationDistance > 0)
            .opacity(trigger.activationDistance > 0 ? 0.5 : 1)

            Section {
                Toggle("Hide trigger from other apps", isOn: $trigger.swallowEvent)
                    .help("Consume the trigger so it doesn't reach the focused app when the wheel opens.")
                Text("When the wheel opens, the trigger never reaches the focused app. A quick tap or click that doesn't open the wheel is delivered on release, so the key/button keeps its normal function (press-and-hold gestures in the other app aren't preserved). Never applied to modifier keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text("Current: \(trigger.displayName)").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Trigger")
    }

    /// Toggle buttons that compose a device-independent modifier chord (matches
    /// either physical side). Keeps at least one modifier selected.
    private var chordBuilder: some View {
        HStack {
            Text("Modifiers")
            Spacer()
            ForEach(TriggerBinding.chordModifiers, id: \.glyph) { modifier in
                Toggle(modifier.glyph, isOn: modifierBinding(modifier.flag))
                    .toggleStyle(.button)
            }
        }
    }

    private var delayLabel: String {
        trigger.activationDelay <= 0
            ? "Off (instant)"
            : "\(Int((trigger.activationDelay * 1000).rounded())) ms"
    }

    private var distanceLabel: String {
        trigger.activationDistance <= 0
            ? "Off"
            : "\(Int(trigger.activationDistance.rounded())) pt"
    }

    private func modifierBinding(_ flag: CGEventFlags) -> Binding<Bool> {
        Binding(
            get: { trigger.code & flag.rawValue != 0 },
            set: { isOn in
                var present = TriggerBinding.chordModifiers
                    .map(\.flag)
                    .filter { trigger.code & $0.rawValue != 0 }
                if isOn {
                    if !present.contains(flag) { present.append(flag) }
                } else {
                    present.removeAll { $0 == flag }
                }
                guard !present.isEmpty else { return } // never leave an empty mask
                trigger = TriggerBinding(
                    kind: .modifier,
                    code: TriggerBinding.chordMask(present),
                    swallowEvent: trigger.swallowEvent,
                    activationDelay: trigger.activationDelay,
                    activationDistance: trigger.activationDistance
                )
            }
        )
    }

    private var presetSelection: Binding<Int?> {
        Binding(
            get: { Self.presets.firstIndex { $0.binding.kind == trigger.kind && $0.binding.code == trigger.code } },
            // Preserve the user's activation tuning (delay + drag distance) when
            // switching which key/button is the trigger.
            set: {
                if let i = $0 {
                    var binding = Self.presets[i].binding
                    binding.activationDelay = trigger.activationDelay
                    binding.activationDistance = trigger.activationDistance
                    trigger = binding
                }
            }
        )
    }
}
