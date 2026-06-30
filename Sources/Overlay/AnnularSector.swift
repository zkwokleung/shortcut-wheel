import SwiftUI

/// A wedge of a ring between `innerRadius` and `outerRadius`. Shared by the live
/// overlay (`WheelView`) and the Settings wheel editor (`WheelLayoutView`).
struct AnnularSector: Shape {
    let angles: (start: Angle, end: Angle)
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    /// Constant-width space (points) trimmed between this wedge and its neighbours.
    /// Applied as a radius-dependent angle so the gap stays a uniform spoke rather
    /// than fanning out toward the rim. `0` makes wedges tile the ring seamlessly.
    var gap: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // Half the gap is taken from each side; a given pixel width subtends a larger
        // angle at a smaller radius, so the inner arc is trimmed more than the outer.
        let span = angles.end.radians - angles.start.radians
        let maxInset = span / 2 * 0.9 // keep the wedge from collapsing on tiny slices
        let outerInset = min(Double(gap / 2 / outerRadius), maxInset)
        let innerInset = min(Double(gap / 2 / max(innerRadius, 1)), maxInset)

        let outerStart = Angle(radians: angles.start.radians + outerInset)
        let outerEnd = Angle(radians: angles.end.radians - outerInset)
        let innerStart = Angle(radians: angles.start.radians + innerInset)
        let innerEnd = Angle(radians: angles.end.radians - innerInset)

        var path = Path()
        path.addArc(center: c, radius: outerRadius, startAngle: outerStart, endAngle: outerEnd, clockwise: false)
        path.addArc(center: c, radius: innerRadius, startAngle: innerEnd, endAngle: innerStart, clockwise: true)
        path.closeSubpath()
        return path
    }
}
