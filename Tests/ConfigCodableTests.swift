import CoreGraphics
import Foundation
import Testing
@testable import ShortcutWheel

struct ConfigCodableTests {
    /// Locks the persisted JSON schema: every Action case must round-trip. This
    /// breaks loudly if a case is renamed/reshaped without a migration.
    @Test func configRoundTripsThroughJSON() throws {
        let wheelID = UUID()
        let config = Config(
            version: Config.currentSchemaVersion,
            wheels: [
                Wheel(id: wheelID, name: "Main", slices: [
                    WheelSlice(label: "Keys", action: .sendKeys(KeyCombo(keyCode: 8, modifiers: .maskCommand))),
                    WheelSlice(label: "URL", action: .openURL("https://example.com")),
                    WheelSlice(label: "App", action: .openApp(path: "/Applications/Safari.app")),
                    WheelSlice(label: "Script", action: .runScript("echo hi")),
                    WheelSlice(label: "Sub", action: .subWheel(wheelID: wheelID)),
                    WheelSlice(label: "Nothing", action: .none),
                ]),
            ],
            trigger: .rightOption,
            rootWheelID: wheelID
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        #expect(decoded == config)
    }

    @Test func wheelWithEmptySlotsRoundTrips() throws {
        let id = UUID()
        let wheel = Wheel(id: id, name: "Sparse", slices: [
            WheelSlice(label: "A", action: .none),
            nil,
            WheelSlice(label: "B", action: .openURL("https://example.com")),
            nil,
        ])
        let config = Config(version: Config.currentSchemaVersion, wheels: [wheel], trigger: .rightOption, rootWheelID: id)

        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        #expect(decoded.wheels[0].slices.count == 4)
        #expect(decoded.wheels[0].slices[1] == nil)
        #expect(decoded.wheels[0].slices[2]?.label == "B")
    }

    @Test func actionHelpers() {
        let id = UUID()
        #expect(Action.subWheel(wheelID: id).isSubWheel)
        #expect(Action.subWheel(wheelID: id).subWheelID == id)
        #expect(!Action.none.isSubWheel)
        #expect(Action.openURL("x").subWheelID == nil)
    }
}
