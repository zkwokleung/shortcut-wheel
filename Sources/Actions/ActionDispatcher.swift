import AppKit
import Foundation
import os

/// Executes a slice's `Action`. Sub-wheel navigation is returned to the caller as
/// an `Outcome` rather than handled here, so the overlay (Phase 5) owns wheel
/// switching while this stays a pure action sink.
@MainActor
struct ActionDispatcher {
    enum Outcome: Equatable {
        case done
        case openSubWheel(UUID)
    }

    private nonisolated static let log = Logger(subsystem: "com.zkwokleung.shortcutwheel", category: "actions")

    @discardableResult
    func perform(_ action: Action) -> Outcome {
        switch action {
        case .sendKeys(let combo):
            KeySynthesizer.post(combo)
        case .openURL(let string):
            guard let url = URL(string: string) else {
                Self.log.error("Invalid URL: \(string, privacy: .public)")
                break
            }
            if !NSWorkspace.shared.open(url) {
                Self.log.error("Failed to open URL: \(string, privacy: .public)")
            }
        case .openApp(let path):
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    Self.log.error("Failed to open app \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        case .runScript(let command):
            runScript(command)
        case .subWheel(let wheelID):
            return .openSubWheel(wheelID)
        case .none:
            break
        }
        return .done
    }

    /// Runs a shell command detached via a login shell. This is a deliberate
    /// security surface — only ever run commands the user authored locally.
    private func runScript(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        // Detach stdio so a chatty script can't block on a full pipe.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Reap the child deterministically and surface non-zero exits.
        process.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                Self.log.error("Script exited with status \(proc.terminationStatus, privacy: .public)")
            }
        }
        do {
            try process.run()
        } catch {
            Self.log.error("Script failed to launch: \(error.localizedDescription, privacy: .public)")
        }
    }
}
