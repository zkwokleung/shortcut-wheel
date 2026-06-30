import Combine
import CoreGraphics
import Foundation
import os

/// Loads and persists the wheel configuration as JSON in Application Support.
/// Mutating `config` (e.g. via Settings bindings) autosaves after a short debounce.
@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()
    private static let log = Logger(subsystem: "com.zkwokleung.shortcutwheel", category: "config")

    @Published var config: Config

    private let fileURL: URL
    private var autosave: AnyCancellable?

    convenience init() {
        self.init(fileURL: Self.configFileURL())
    }

    /// Designated init; `fileURL` is injectable so tests can use a temp file.
    init(fileURL: URL) {
        self.fileURL = fileURL
        if let loaded = Self.load(from: fileURL) {
            config = loaded
        } else {
            config = Self.defaultConfig()
            save()
        }

        autosave = $config
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    var trigger: TriggerBinding { config.trigger }
    var rootWheel: Wheel? { wheel(id: config.rootWheelID) }

    func wheel(id: UUID) -> Wheel? {
        config.wheels.first { $0.id == id }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.log.error("Failed to save config: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> Config? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // Don't silently destroy an unreadable file (corrupt, or a forward-
            // incompatible schema) — preserve it so the user can recover.
            log.error("Failed to decode config; backing up and using defaults: \(error.localizedDescription, privacy: .public)")
            backUpCorruptFile(at: url)
            return nil
        }
    }

    private static func backUpCorruptFile(at url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("config.corrupt-\(stamp).json", isDirectory: false)
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    private static func configFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("ShortcutWheel", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    static func defaultConfig() -> Config {
        let cmd = CGEventFlags.maskCommand
        // Virtual key codes (US layout): C=8, V=9, Space=49.
        let child = Wheel(name: "Tools", slices: [
            WheelSlice(label: "Notify", symbol: "bell", tintHex: "#E0A458",
                  action: .runScript("osascript -e 'display notification \"Hello from ShortcutWheel\"'")),
            WheelSlice(label: "Finder", symbol: "folder", tintHex: "#5BD6C0",
                  action: .openApp(path: "/System/Library/CoreServices/Finder.app")),
            WheelSlice(label: "Google", symbol: "magnifyingglass", tintHex: "#EF6F6C",
                  action: .openURL("https://www.google.com")),
        ])

        let root = Wheel(name: "Main", slices: [
            WheelSlice(label: "Copy", symbol: "doc.on.doc", tintHex: "#5B8DEF",
                  action: .sendKeys(KeyCombo(keyCode: 8, modifiers: cmd))),
            WheelSlice(label: "Paste", symbol: "doc.on.clipboard", tintHex: "#57B894",
                  action: .sendKeys(KeyCombo(keyCode: 9, modifiers: cmd))),
            WheelSlice(label: "Spotlight", symbol: "magnifyingglass", tintHex: "#E0A458",
                  action: .sendKeys(KeyCombo(keyCode: 49, modifiers: cmd))),
            WheelSlice(label: "Safari", symbol: "safari", tintHex: "#EF6F6C",
                  action: .openApp(path: "/Applications/Safari.app")),
            WheelSlice(label: "Terminal", symbol: "terminal", tintHex: "#9B8CEF",
                  action: .openApp(path: "/System/Applications/Utilities/Terminal.app")),
            WheelSlice(label: "Tools…", symbol: "ellipsis.circle", tintHex: "#7A869A",
                  action: .subWheel(wheelID: child.id)),
        ])

        return Config(
            version: Config.currentSchemaVersion,
            wheels: [root, child],
            trigger: .rightOption,
            rootWheelID: root.id
        )
    }
}
