import CoreGraphics
import Foundation
import SwiftUI

/// Pure geometry for the radial menu. Selection is by cursor *direction* from the
/// wheel center, not by hit-testing, so the cursor may travel outside the panel.
///
/// Two coordinate spaces are in play:
/// - **Screen space** (`NSEvent.mouseLocation`): origin bottom-left, y points up.
///   Selection math lives here.
/// - **View space** (SwiftUI): origin top-left, y points down. `labelPosition`
///   converts into it for drawing.
///
/// Angles are measured **clockwise from the top** (12 o'clock = 0), so slice 0 is
/// centered at the top and slices proceed clockwise.
enum WheelGeometry {
    /// Cursor closer than this to the center selects nothing (a release here cancels).
    static let deadZoneRadius: CGFloat = 28

    /// Constant-width space (points) drawn between adjacent wedges. Shared by the
    /// live overlay and the settings preview so they render identically.
    static let wedgeGap: CGFloat = 4

    /// Slice the cursor points at, or `nil` if within the dead zone / no slices.
    /// `cursor` and `center` are both in screen space (y-up). When `maxRadius` is
    /// given (precise-position mode), a cursor farther than it from the center also
    /// selects nothing; `nil` (direction mode) leaves selection unbounded outward.
    static func sliceIndex(forCursor cursor: CGPoint, center: CGPoint, sliceCount: Int,
                           maxRadius: CGFloat? = nil) -> Int? {
        guard sliceCount > 0 else { return nil }

        let dx = cursor.x - center.x
        let dy = cursor.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= deadZoneRadius else { return nil }
        if let maxRadius, distance > maxRadius { return nil }

        // atan2(dx, dy): top → 0, right → +π/2, bottom → ±π, left → -π/2.
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * .pi }

        let sliceAngle = 2 * .pi / CGFloat(sliceCount)
        let index = Int((angle / sliceAngle).rounded()) % sliceCount
        return index
    }

    /// Center angle of a slice, clockwise from top, in radians.
    static func centerAngle(of index: Int, sliceCount: Int) -> CGFloat {
        guard sliceCount > 0 else { return 0 }
        return CGFloat(index) * (2 * .pi / CGFloat(sliceCount))
    }

    /// Position for a slice's label at `radius`, in view space (y-down) around
    /// `center`. Converts the clockwise-from-top angle into screen drawing coords.
    static func labelPosition(index: Int, sliceCount: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = centerAngle(of: index, sliceCount: sliceCount)
        return CGPoint(
            x: center.x + radius * sin(angle),
            y: center.y - radius * cos(angle)
        )
    }

    /// Start/end angles for a slice's full sector as SwiftUI `Angle`s (0 = east,
    /// y-down so increasing angle is visually clockwise). Wedges tile the whole ring;
    /// `AnnularSector.gap` trims a constant-width space between them when drawing.
    static func sectorAngles(index: Int, sliceCount: Int) -> (start: Angle, end: Angle) {
        let sliceAngle = 2 * .pi / CGFloat(sliceCount)
        let center = centerAngle(of: index, sliceCount: sliceCount)
        // Convert clockwise-from-top to SwiftUI's east-origin: subtract 90°.
        let swCenter = center - .pi / 2
        let half = sliceAngle / 2
        return (Angle(radians: Double(swCenter - half)), Angle(radians: Double(swCenter + half)))
    }
}
