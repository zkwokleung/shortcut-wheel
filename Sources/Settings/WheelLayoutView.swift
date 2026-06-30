import SwiftUI

/// Interactive preview of a wheel's slots, mirroring the live overlay layout
/// (`WheelGeometry` + `AnnularSector`). Tapping a wedge reports its slot index;
/// empty slots show a "+" and filled slots show their tint/symbol/label.
struct WheelLayoutView: View {
    @Binding var slices: [WheelSlice?]
    let onSelectSlot: (Int) -> Void

    private let diameter: CGFloat = 300
    private let outerRadius: CGFloat = 138
    private let innerRadius: CGFloat = 46
    private var labelRadius: CGFloat { (outerRadius + innerRadius) / 2 }
    private var center: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }

    var body: some View {
        ZStack {
            ForEach(slices.indices, id: \.self) { index in
                wedge(at: index)
            }
            ForEach(slices.indices, id: \.self) { index in
                label(at: index)
            }
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: innerRadius * 2 - 6, height: innerRadius * 2 - 6)
                .overlay(Circle().stroke(.secondary.opacity(0.25)))
                .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
    }

    private func wedge(at index: Int) -> some View {
        let shape = AnnularSector(
            angles: WheelGeometry.sectorAngles(index: index, sliceCount: slices.count),
            innerRadius: innerRadius,
            outerRadius: outerRadius
        )
        let slot = slices[index]
        let fill = slot.map { Color(hex: $0.tintHex).opacity(0.85) } ?? Color.gray.opacity(0.15)
        return shape
            .fill(fill)
            .overlay(shape.stroke(.secondary.opacity(0.35), lineWidth: 1))
            .contentShape(shape)
            .onTapGesture { onSelectSlot(index) }
    }

    @ViewBuilder
    private func label(at index: Int) -> some View {
        let position = WheelGeometry.labelPosition(
            index: index, sliceCount: slices.count, center: center, radius: labelRadius
        )
        Group {
            if let slot = slices[index] {
                VStack(spacing: 2) {
                    Image(systemName: slot.symbol ?? "circle.fill").font(.system(size: 16, weight: .semibold))
                    Text(slot.label.isEmpty ? "Untitled" : slot.label).font(.caption2).lineLimit(1)
                    if slot.action.isSubWheel {
                        Image(systemName: "chevron.right.2").font(.system(size: 7, weight: .bold)).opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
            } else {
                Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .position(position)
        .allowsHitTesting(false) // taps belong to the wedge underneath
    }
}
