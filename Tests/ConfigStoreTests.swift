import Foundation
import Testing
@testable import ShortcutWheel

@MainActor
struct ConfigStoreTests {
    @Test func defaultConfigIsInternallyConsistent() {
        let config = ConfigStore.defaultConfig()
        let ids = Set(config.wheels.map(\.id))
        // Root must exist, and every sub-wheel reference must resolve.
        #expect(ids.contains(config.rootWheelID))
        for wheel in config.wheels {
            for case let slice? in wheel.slices {
                if let sub = slice.action.subWheelID {
                    #expect(ids.contains(sub))
                }
            }
        }
    }

    @Test func savesAndReloads() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ConfigStore(fileURL: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reloaded = ConfigStore(fileURL: url)
        #expect(reloaded.config == store.config)
    }

    @Test func corruptFileIsBackedUpNotDestroyed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("config.json")
        try Data("this is not json".utf8).write(to: url)

        _ = ConfigStore(fileURL: url) // should back up the bad file and write defaults

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("config.corrupt-") })
        #expect(files.contains("config.json"))
    }
}
