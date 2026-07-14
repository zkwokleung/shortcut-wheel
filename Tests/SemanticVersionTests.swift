import Testing
@testable import ShortcutWheel

struct SemanticVersionTests {
    @Test func parsesLeadingV() {
        #expect(SemanticVersion("v1.2.3") == SemanticVersion("1.2.3"))
    }

    @Test func ordersNumericallyNotLexically() {
        let v = ["0.1.0", "0.2.0", "0.10.0", "1.0.0"].compactMap { SemanticVersion($0) }
        #expect(v == v.sorted())
        #expect(SemanticVersion("0.10.0")! > SemanticVersion("0.2.0")!)
    }

    @Test func missingComponentsAreZero() {
        #expect(SemanticVersion("1.2") == SemanticVersion("1.2.0"))
        #expect(SemanticVersion("1")! < SemanticVersion("1.0.1")!)
    }

    @Test func ignoresPreReleaseAndBuildSuffix() {
        #expect(SemanticVersion("1.2.0-beta.1") == SemanticVersion("1.2.0"))
        #expect(SemanticVersion("v2.0.0+build7") == SemanticVersion("2.0.0"))
    }

    @Test func rejectsMalformed() {
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("v") == nil)
        #expect(SemanticVersion("latest") == nil)
    }
}
