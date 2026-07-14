import Foundation
import Testing
@testable import ShortcutWheel

@MainActor
struct UpdateCheckerTests {
    private static func payload(tag: String, withDMG: Bool = true) -> Data {
        let asset = withDMG
            ? #"{"browser_download_url": "https://example.com/ShortcutWheel-\#(tag).dmg"}"#
            : #"{"browser_download_url": "https://example.com/notes.txt"}"#
        return Data(#"""
        {
          "tag_name": "\#(tag)",
          "html_url": "https://github.com/zkwokleung/shortcut-wheel/releases/tag/\#(tag)",
          "body": "Release notes",
          "assets": [\#(asset)]
        }
        """#.utf8)
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suite = "sw-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeChecker(current: String, fetch: @escaping (URL) async throws -> Data) -> UpdateChecker {
        UpdateChecker(currentVersion: current, defaults: Self.isolatedDefaults(), fetch: fetch)
    }

    @Test func reportsAvailableWhenRemoteIsNewer() async {
        let checker = makeChecker(current: "1.0.0") { _ in Self.payload(tag: "v2.0.0") }
        await checker.check(userInitiated: true)
        guard case .available(let release) = checker.state else {
            Issue.record("expected .available, got \(checker.state)")
            return
        }
        #expect(release.version == "2.0.0")
        #expect(release.dmgURL?.absoluteString.hasSuffix(".dmg") == true)
    }

    @Test func reportsUpToDateWhenRemoteIsNotNewer() async {
        let checker = makeChecker(current: "2.0.0") { _ in Self.payload(tag: "v1.5.0") }
        await checker.check(userInitiated: true)
        #expect(checker.state == .upToDate)
    }

    @Test func nilDMGWhenNoDMGAsset() async {
        let checker = makeChecker(current: "1.0.0") { _ in Self.payload(tag: "v2.0.0", withDMG: false) }
        await checker.check(userInitiated: true)
        guard case .available(let release) = checker.state else {
            Issue.record("expected .available, got \(checker.state)")
            return
        }
        #expect(release.dmgURL == nil)
    }

    @Test func reportsFailedOnFetchError() async {
        struct Boom: Error {}
        let checker = makeChecker(current: "1.0.0") { _ in throw Boom() }
        await checker.check(userInitiated: true)
        guard case .failed = checker.state else {
            Issue.record("expected .failed, got \(checker.state)")
            return
        }
    }

    @Test func autoCheckIsThrottled() async {
        var calls = 0
        let checker = makeChecker(current: "1.0.0") { _ in
            calls += 1
            return Self.payload(tag: "v1.0.0")
        }
        await checker.check(userInitiated: false) // first auto-check runs and records the timestamp
        await checker.check(userInitiated: false) // within window → skipped
        #expect(calls == 1)

        await checker.check(userInitiated: true) // manual bypasses the throttle
        #expect(calls == 2)
    }
}
