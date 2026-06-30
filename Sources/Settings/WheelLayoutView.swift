import SwiftUI

/// Interactive preview of a wheel's slots, mirroring the live overlay layout
/// (`WheelGeometry` + `AnnularSector`). Tapping a wedge reports its slot index;
/// dragging a filled wedge onto another position swaps the two slices (swapping
/// with an empty slot moves it there). Empty slots show a "+" and filled slots
/// show their tint/symbol/label.
struct WheelLayoutView: View {
    @Binding var slices: [WheelSlice?]
    var selectionMode: SelectionMode = .direction
    let onSelectSlot: (Int) -> Void

    private let diameter: CGFloat = 300
    private let outerRadius: CGFloat = 138
    private let innerRadius: CGFloat = 46
    private var labelRadius: CGFloat { (outerRadius + innerRadius) / 2 }
    private var center: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }

    @State private var dragSourceIndex: Int?
    @State private var dragLocation: CGPoint?
    @State private var dropTargetIndex: Int?

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

            if let source = dragSourceIndex, let location = dragLocation, let slot = slices[source] {
                dragChip(for: slot)
                    .position(location)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func wedge(at index: Int) -> some View {
        let angles = WheelGeometry.sectorAngles(index: index, sliceCount: slices.count)
        let shape = AnnularSector(angles: angles, innerRadius: innerRadius, outerRadius: outerRadius, gap: WheelGeometry.wedgeGap)
        // Ungapped hit area so taps near a wedge border still register on it.
        let hitShape = AnnularSector(angles: angles, innerRadius: innerRadius, outerRadius: outerRadius)
        let slot = slices[index]
        let fill = slot.map { Color(hex: $0.tintHex).opacity(0.85) } ?? Color.gray.opacity(0.15)
        let isSource = dragSourceIndex == index
        let isDropTarget = dropTargetIndex == index && dragSourceIndex != nil && dragSourceIndex != index
        let stroke: AnyShapeStyle = isDropTarget ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary.opacity(0.35))
        return shape
            .fill(fill)
            .overlay(shape.stroke(stroke, lineWidth: isDropTarget ? 3 : 1))
            .opacity(isSource ? 0.4 : 1)
            .contentShape(hitShape)
            .onTapGesture { onSelectSlot(index) }
            .gesture(dragGesture(for: index))
    }

    /// Drag past `minimumDistance` reorders; a tap below it falls through to
    /// `onSelectSlot`. Only filled slots can be picked up. The drop commits the
    /// highlighted `dropTargetIndex`, so what the user sees is what they get and a
    /// release on no target (dead zone, or off the wheel in precise mode) cancels.
    private func dragGesture(for index: Int) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard slices[index] != nil else { return }
                if dragSourceIndex == nil { dragSourceIndex = index }
                dragLocation = value.location
                dropTargetIndex = targetIndex(at: value.location)
            }
            .onEnded { _ in
                defer {
                    dragSourceIndex = nil
                    dragLocation = nil
                    dropTargetIndex = nil
                }
                guard let source = dragSourceIndex, let target = dropTargetIndex, target != source else { return }
                slices.swapAt(source, target)
            }
    }

    /// Slot under a view-space drag point. `WheelGeometry` works in screen space
    /// (y-up), so flip y; `center` is symmetric and needs no flip. Precise mode
    /// bounds the drop to the wheel so a release off it resolves to no target.
    private func targetIndex(at point: CGPoint) -> Int? {
        let flipped = CGPoint(x: point.x, y: diameter - point.y)
        let maxRadius: CGFloat? = selectionMode == .precisePosition ? outerRadius : nil
        return WheelGeometry.sliceIndex(forCursor: flipped, center: center, sliceCount: slices.count, maxRadius: maxRadius)
    }

    @ViewBuilder
    private func label(at index: Int) -> some View {
        let position = WheelGeometry.labelPosition(
            index: index, sliceCount: slices.count, center: center, radius: labelRadius
        )
        Group {
            if let slot = slices[index] {
                VStack(spacing: 2) {
                    sliceLabelContent(slot)
                    if slot.action.isSubWheel {
                        Image(systemName: "chevron.right.2").font(.system(size: 7, weight: .bold)).opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
            } else {
                Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .opacity(dragSourceIndex == index ? 0 : 1) // hidden while lifted; the drag chip stands in
        .position(position)
        .allowsHitTesting(false) // taps belong to the wedge underneath
    }

    /// The symbol + title shared by a wedge's resting label and its lifted drag chip,
    /// so the two always render the slice identically.
    @ViewBuilder
    private func sliceLabelContent(_ slot: WheelSlice) -> some View {
        Image(systemName: slot.symbol ?? "circle.fill").font(.system(size: 16, weight: .semibold))
        Text(slot.label.isEmpty ? "Untitled" : slot.label).font(.caption2).lineLimit(1)
    }

    private func dragChip(for slot: WheelSlice) -> some View {
        VStack(spacing: 2) {
            sliceLabelContent(slot)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: slot.tintHex).opacity(0.95)))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}
