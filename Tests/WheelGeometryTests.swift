import CoreGraphics
import Testing
@testable import ShortcutWheel

struct WheelGeometryTests {
    private let center = CGPoint(x: 100, y: 100)

    @Test func cardinalDirectionsMapToExpectedSlices() {
        // 4 slices, clockwise from top: 0=N, 1=E, 2=S, 3=W (screen space, y-up).
        #expect(WheelGeometry.sliceIndex(forCursor: CGPoint(x: 100, y: 160), center: center, sliceCount: 4) == 0)
        #expect(WheelGeometry.sliceIndex(forCursor: CGPoint(x: 160, y: 100), center: center, sliceCount: 4) == 1)
        #expect(WheelGeometry.sliceIndex(forCursor: CGPoint(x: 100, y: 40), center: center, sliceCount: 4) == 2)
        #expect(WheelGeometry.sliceIndex(forCursor: CGPoint(x: 40, y: 100), center: center, sliceCount: 4) == 3)
    }

    @Test func cursorInsideDeadZoneSelectsNothing() {
        let inside = CGPoint(x: center.x + WheelGeometry.deadZoneRadius - 1, y: center.y)
        #expect(WheelGeometry.sliceIndex(forCursor: inside, center: center, sliceCount: 6) == nil)
    }

    @Test func seamWrapsAroundWithoutOffByOne() {
        // Just counter-clockwise of straight-up should round back to slice 0, not 6.
        let nearTop = CGPoint(x: 99, y: 200)
        #expect(WheelGeometry.sliceIndex(forCursor: nearTop, center: center, sliceCount: 6) == 0)
    }

    @Test func zeroSlicesIsNil() {
        #expect(WheelGeometry.sliceIndex(forCursor: CGPoint(x: 200, y: 100), center: center, sliceCount: 0) == nil)
    }

    @Test func sectorAnglesNeverInvertForManySlices() {
        // Each wedge must span forward (start <= end) for any slice count.
        for count in [2, 6, 12, 60] {
            for i in 0..<count {
                let (start, end) = WheelGeometry.sectorAngles(index: i, sliceCount: count)
                #expect(start.radians <= end.radians)
            }
        }
    }
}
