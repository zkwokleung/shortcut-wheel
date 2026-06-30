import Testing
@testable import ShortcutWheel

struct WheelResizeTests {
    private func slice(_ label: String) -> WheelSlice {
        WheelSlice(label: label, action: .none)
    }

    private func labels(_ wheel: Wheel) -> [String?] {
        wheel.slices.map { $0?.label }
    }

    @Test func emptySlotCountCountsNils() {
        let wheel = Wheel(name: "W", slices: [slice("A"), nil, slice("B"), nil])
        #expect(wheel.emptySlotCount == 2)
    }

    @Test func removalPrefersEmptySlotsOverFilled() {
        var wheel = Wheel(name: "W", slices: [slice("A"), nil, slice("B")])
        wheel.removeSlots(1)
        #expect(labels(wheel) == ["A", "B"])
    }

    @Test func trailingEmptiesGoBeforeInteriorEmpties() {
        var wheel = Wheel(name: "W", slices: [nil, slice("A"), nil])
        wheel.removeSlots(1)
        #expect(labels(wheel) == [nil, "A"])
    }

    @Test func emptiesRemovedFirstThenFilledFromEnd() {
        var wheel = Wheel(name: "W", slices: [slice("A"), nil, slice("B"), slice("C")])
        wheel.removeSlots(2)
        #expect(labels(wheel) == ["A", "B"])
    }

    @Test func removingMoreThanCountClampsToEmpty() {
        var wheel = Wheel(name: "W", slices: [slice("A"), nil])
        wheel.removeSlots(99)
        #expect(wheel.slices.isEmpty)
    }

    @Test func removingZeroOrNegativeIsNoOp() {
        var wheel = Wheel(name: "W", slices: [slice("A"), nil])
        wheel.removeSlots(0)
        #expect(labels(wheel) == ["A", nil])
        wheel.removeSlots(-3)
        #expect(labels(wheel) == ["A", nil])
    }
}
