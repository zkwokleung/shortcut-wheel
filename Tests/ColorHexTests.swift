import SwiftUI
import Testing
@testable import ShortcutWheel

struct ColorHexTests {
    @Test(arguments: ["#5B8DEF", "#000000", "#FFFFFF", "#E0A458", "#57B894"])
    func roundTripIsStable(hex: String) {
        // Parse → re-encode must yield the same canonical hex (8-bit quantized).
        #expect(Color(hex: hex).hexString == hex)
    }

    @Test func shorthandExpands() {
        #expect(Color(hex: "#0F0").hexString == "#00FF00")
        #expect(Color(hex: "F00").hexString == "#FF0000")
    }

    @Test func whitespaceTolerated() {
        #expect(Color(hex: "  #5B8DEF \n").hexString == "#5B8DEF")
    }

    @Test func invalidFallsBackToGray() {
        #expect(Color(hex: "nonsense").hexString == Color.gray.hexString)
        #expect(Color(hex: "#12").hexString == Color.gray.hexString)
    }
}
