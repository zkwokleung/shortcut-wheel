import SwiftUI

/// A wedge of a ring between `innerRadius` and `outerRadius`. Shared by the live
/// overlay (`WheelView`) and the Settings wheel editor (`WheelLayoutView`).
struct AnnularSector: Shape {
    let angles: (start: Angle, end: Angle)
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: c, radius: outerRadius, startAngle: angles.start, endAngle: angles.end, clockwise: false)
        path.addArc(center: c, radius: innerRadius, startAngle: angles.end, endAngle: angles.start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
