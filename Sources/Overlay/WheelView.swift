import SwiftUI

/// What a single slice shows. Decoupled from the persisted model (Phase 4) so the
/// view stays purely presentational.
struct SliceDisplay: Identifiable, Equatable {
    let id: Int
    let label: String
    let symbol: String?
    let tint: Color
    let isSubWheel: Bool
    /// An unassigned slot: drawn dimmed with no label, and inert (no action/dwell).
    let isEmpty: Bool
}

/// Drives `WheelView`. The overlay controller computes `selectedIndex` from the
/// live cursor and publishes it here, along with dwell progress (0...1) used to
/// drill into / out of sub-wheels.
@MainActor
final class WheelViewModel: ObservableObject {
    @Published var slices: [SliceDisplay] = []
    @Published var selectedIndex: Int?
    @Published var dwellProgress: Double = 0
    @Published var canGoBack = false
}

struct WheelView: View {
    @ObservedObject var model: WheelViewModel

    private let outerRadius: CGFloat = 132
    private let innerRadius: CGFloat = 52
    private var labelRadius: CGFloat { (outerRadius + innerRadius) / 2 }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                sectors
                labels(center: center)
                centerHub
                dwellIndicator(center: center)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeOut(duration: 0.08), value: model.selectedIndex)
    }

    private var sectors: some View {
        ForEach(model.slices) { slice in
            let selected = model.selectedIndex == slice.id
            let fillOpacity = slice.isEmpty ? 0.12 : (selected ? 1.0 : 0.55)
            let shape = AnnularSector(
                angles: WheelGeometry.sectorAngles(index: slice.id, sliceCount: model.slices.count),
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                gap: WheelGeometry.wedgeGap
            )
            shape
                .fill((slice.isEmpty ? Color.white : slice.tint).opacity(fillOpacity))
                .overlay(shape.stroke(.white.opacity(selected && !slice.isEmpty ? 0.9 : 0.15),
                                      lineWidth: selected && !slice.isEmpty ? 2 : 1))
                .shadow(color: .black.opacity(slice.isEmpty ? 0 : 0.25), radius: 8, y: 2)
        }
    }

    private func labels(center: CGPoint) -> some View {
        ForEach(model.slices.filter { !$0.isEmpty }) { slice in
            let selected = model.selectedIndex == slice.id
            VStack(spacing: 3) {
                if let symbol = slice.symbol {
                    Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                }
                Text(slice.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if slice.isSubWheel {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(.white)
            .opacity(selected ? 1.0 : 0.85)
            .scaleEffect(selected ? 1.12 : 1.0)
            .position(
                WheelGeometry.labelPosition(
                    index: slice.id,
                    sliceCount: model.slices.count,
                    center: center,
                    radius: labelRadius
                )
            )
        }
    }

    private var centerHub: some View {
        Circle()
            .fill(.black.opacity(0.45))
            .frame(width: WheelGeometry.deadZoneRadius * 2, height: WheelGeometry.deadZoneRadius * 2)
            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
            .overlay(centerGlyph)
    }

    /// An empty slot is not an actionable selection, so the hub should read like the
    /// center (cancel / back), not "something is selected".
    private var hasActionableSelection: Bool {
        guard let index = model.selectedIndex, model.slices.indices.contains(index) else { return false }
        return !model.slices[index].isEmpty
    }

    private var centerGlyph: some View {
        let atCenter = !hasActionableSelection
        let symbol = atCenter ? (model.canGoBack ? "chevron.backward" : "xmark") : "circle.fill"
        return Image(systemName: symbol)
            .font(.system(size: atCenter ? 13 : 7, weight: .bold))
            .foregroundStyle(.white.opacity(atCenter ? 0.7 : 0.4))
    }

    /// A ring that fills while the cursor dwells on a sub-wheel slice (to drill in)
    /// or in the center when nested (to go back).
    @ViewBuilder
    private func dwellIndicator(center: CGPoint) -> some View {
        if model.dwellProgress > 0 {
            let position: CGPoint = model.selectedIndex.map {
                WheelGeometry.labelPosition(index: $0, sliceCount: model.slices.count, center: center, radius: labelRadius)
            } ?? center
            Circle()
                .trim(from: 0, to: model.dwellProgress)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))
                .position(position)
        }
    }
}
