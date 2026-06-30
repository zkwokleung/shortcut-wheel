import SwiftUI

struct WheelEditorView: View {
    @Binding var wheel: Wheel
    let isRoot: Bool
    let otherWheels: [Wheel]
    let makeRoot: () -> Void

    @State private var editingSlot: EditingSlot?
    @State private var pendingSlotCount: Int?

    private let slotRange = 2...12

    var body: some View {
        Form {
            Section("Wheel") {
                TextField("Name", text: $wheel.name)
                Stepper(value: slotCountBinding, in: slotRange) {
                    LabeledContent("Positions", value: "\(wheel.slices.count)")
                }
                if isRoot {
                    Label("Opens on trigger", systemImage: "smallcircle.filled.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Make This the Default Wheel", action: makeRoot)
                }
            }

            Section("Layout") {
                WheelLayoutView(slices: $wheel.slices) { slot in
                    if wheel.slices[slot] == nil {
                        wheel.slices[slot] = WheelSlice(label: "New Slice", action: .none)
                    }
                    editingSlot = EditingSlot(index: slot)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                Text("Tap a wedge to assign or edit the shortcut at that position.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(wheel.name.isEmpty ? "Wheel" : wheel.name)
        .sheet(item: $editingSlot) { slot in
            if let binding = sliceBinding(slot.index) {
                SliceEditorView(
                    slice: binding,
                    otherWheels: otherWheels,
                    onClear: {
                        if wheel.slices.indices.contains(slot.index) { wheel.slices[slot.index] = nil }
                        editingSlot = nil
                    },
                    onDone: { editingSlot = nil }
                )
            }
        }
        .confirmationDialog(
            "Remove positions?",
            isPresented: Binding(get: { pendingSlotCount != nil }, set: { if !$0 { pendingSlotCount = nil } }),
            presenting: pendingSlotCount
        ) { newCount in
            Button("Remove", role: .destructive) {
                let drop = wheel.slices.count - newCount
                if drop > 0 { wheel.slices.removeLast(drop) }
                pendingSlotCount = nil
            }
            Button("Cancel", role: .cancel) { pendingSlotCount = nil }
        } message: { _ in
            Text("Some of the removed positions have shortcuts assigned. They will be deleted.")
        }
    }

    private var slotCountBinding: Binding<Int> {
        Binding(get: { wheel.slices.count }, set: { setSlotCount($0) })
    }

    private func setSlotCount(_ newCount: Int) {
        let current = wheel.slices.count
        guard newCount != current else { return }
        if newCount > current {
            wheel.slices.append(contentsOf: Array(repeating: nil, count: newCount - current))
        } else if wheel.slices[newCount...].contains(where: { $0 != nil }) {
            pendingSlotCount = newCount // confirm before dropping filled slots
        } else {
            wheel.slices.removeLast(current - newCount)
        }
    }

    /// Binds the (filled) slot at `index` as a non-optional `WheelSlice`. Safe while
    /// the sheet is open: slots don't reorder, and the getter tolerates a clear.
    private func sliceBinding(_ index: Int) -> Binding<WheelSlice>? {
        guard wheel.slices.indices.contains(index), let current = wheel.slices[index] else { return nil }
        let wheelBinding = $wheel
        return Binding(
            get: {
                guard wheelBinding.wrappedValue.slices.indices.contains(index) else { return current }
                return wheelBinding.wrappedValue.slices[index] ?? current
            },
            set: { newValue in
                if wheelBinding.wrappedValue.slices.indices.contains(index) {
                    wheelBinding.wrappedValue.slices[index] = newValue
                }
            }
        )
    }
}

private struct EditingSlot: Identifiable {
    let index: Int
    var id: Int { index }
}
