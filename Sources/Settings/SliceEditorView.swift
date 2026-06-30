import AppKit
import SwiftUI

struct SliceEditorView: View {
    @Binding var slice: WheelSlice
    let otherWheels: [Wheel]
    var onClear: (() -> Void)?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Appearance") {
                    TextField("Label", text: $slice.label)
                    HStack {
                        TextField("SF Symbol", text: symbolBinding)
                        Image(systemName: slice.symbol ?? "circle")
                            .foregroundStyle(Color(hex: slice.tintHex))
                    }
                    ColorPicker("Tint", selection: tintBinding, supportsOpacity: false)
                }

                Section("Action") {
                    Picker("Type", selection: kindBinding) {
                        ForEach(availableKinds) { Text($0.label).tag($0) }
                    }
                    actionFields
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let onClear {
                    Button("Remove From Wheel", role: .destructive, action: onClear)
                }
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 440)
    }

    @ViewBuilder
    private var actionFields: some View {
        switch slice.action {
        case .sendKeys:
            Toggle("⌘ Command", isOn: modifierBinding(.maskCommand))
            Toggle("⌥ Option", isOn: modifierBinding(.maskAlternate))
            Toggle("⌃ Control", isOn: modifierBinding(.maskControl))
            Toggle("⇧ Shift", isOn: modifierBinding(.maskShift))
            HStack {
                Text("Key code")
                TextField("", value: keyCodeBinding, format: .number).frame(width: 60)
                Text("e.g. C=8, V=9, Space=49").font(.caption).foregroundStyle(.secondary)
            }
        case .openURL:
            TextField("https://example.com", text: stringBinding(get: openURLValue, set: { slice.action = .openURL($0) }))
        case .openApp:
            HStack {
                TextField("/Applications/Safari.app", text: stringBinding(get: openAppValue, set: { slice.action = .openApp(path: $0) }))
                Button("Choose…", action: chooseApp)
            }
        case .runScript:
            TextField("shell command", text: stringBinding(get: runScriptValue, set: { slice.action = .runScript($0) }), axis: .vertical)
                .lineLimit(3...6)
            Label("Runs via /bin/zsh. Only enter commands you trust.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        case .subWheel:
            if otherWheels.isEmpty {
                Text("Create another wheel first.").foregroundStyle(.secondary)
            } else {
                Picker("Wheel", selection: subWheelBinding) {
                    ForEach(otherWheels) { Text($0.name).tag($0.id) }
                }
            }
        case .openSettings:
            Text("Opens Shortcut Wheel's settings window.").foregroundStyle(.secondary)
        case .none:
            Text("This slice does nothing when selected.").foregroundStyle(.secondary)
        }
    }

    // MARK: Appearance bindings

    private var symbolBinding: Binding<String> {
        Binding(get: { slice.symbol ?? "" }, set: { slice.symbol = $0.isEmpty ? nil : $0 })
    }

    private var tintBinding: Binding<Color> {
        Binding(get: { Color(hex: slice.tintHex) }, set: { slice.tintHex = $0.hexString })
    }

    // MARK: Action-kind binding

    /// Sub-wheel is only offered when there's another wheel to point at (or the
    /// slice already is one, so it stays selectable while being changed away).
    private var availableKinds: [ActionKind] {
        ActionKind.allCases.filter { $0 != .subWheel || !otherWheels.isEmpty || slice.action.isSubWheel }
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(get: { ActionKind(slice.action) }, set: { setKind($0) })
    }

    private func setKind(_ kind: ActionKind) {
        guard kind != ActionKind(slice.action) else { return }
        switch kind {
        case .none: slice.action = .none
        case .sendKeys: slice.action = .sendKeys(KeyCombo(keyCode: 8, modifiers: .maskCommand))
        case .openURL: slice.action = .openURL("https://")
        case .openApp: slice.action = .openApp(path: "/Applications/")
        case .runScript: slice.action = .runScript("")
        case .subWheel:
            guard let target = otherWheels.first?.id else { return }
            slice.action = .subWheel(wheelID: target)
        case .openSettings:
            slice.action = .openSettings
        }
    }

    // MARK: sendKeys helpers

    private var combo: KeyCombo {
        if case .sendKeys(let c) = slice.action { return c }
        return KeyCombo(keyCode: 0)
    }

    private func modifierBinding(_ flag: CGEventFlags) -> Binding<Bool> {
        Binding(
            get: { combo.flags.contains(flag) },
            set: { on in
                var raw = combo.modifiers
                if on { raw |= flag.rawValue } else { raw &= ~flag.rawValue }
                var updated = combo
                updated.modifiers = raw
                slice.action = .sendKeys(updated)
            }
        )
    }

    private var keyCodeBinding: Binding<Int> {
        Binding(
            get: { Int(combo.keyCode) },
            set: {
                var updated = combo
                updated.keyCode = UInt16(min(max($0, 0), 127))
                slice.action = .sendKeys(updated)
            }
        )
    }

    // MARK: value extractors

    private func openURLValue() -> String { if case .openURL(let s) = slice.action { return s }; return "" }
    private func openAppValue() -> String { if case .openApp(let p) = slice.action { return p }; return "" }
    private func runScriptValue() -> String { if case .runScript(let c) = slice.action { return c }; return "" }

    private func stringBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: get, set: set)
    }

    private var subWheelBinding: Binding<UUID> {
        Binding(
            get: { slice.action.subWheelID ?? otherWheels.first?.id ?? UUID() },
            set: { slice.action = .subWheel(wheelID: $0) }
        )
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            slice.action = .openApp(path: url.path)
        }
    }
}

private enum ActionKind: String, CaseIterable, Identifiable {
    case none, sendKeys, openURL, openApp, runScript, subWheel, openSettings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .sendKeys: return "Send Keystrokes"
        case .openURL: return "Open URL"
        case .openApp: return "Open App"
        case .runScript: return "Run Script"
        case .subWheel: return "Sub-wheel"
        case .openSettings: return "Open Settings"
        }
    }

    init(_ action: Action) {
        switch action {
        case .none: self = .none
        case .sendKeys: self = .sendKeys
        case .openURL: self = .openURL
        case .openApp: self = .openApp
        case .runScript: self = .runScript
        case .subWheel: self = .subWheel
        case .openSettings: self = .openSettings
        }
    }
}

extension Color {
    /// `#RRGGBB` in sRGB. Falls back to the gray hex if components can't be read.
    var hexString: String {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return "#808080" }
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
