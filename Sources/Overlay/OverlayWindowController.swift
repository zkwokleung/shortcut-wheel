import AppKit
import os
import QuartzCore
import SwiftUI

/// A borderless, non-activating panel that never takes key focus — so the app the
/// user was in stays focused and synthesized keystrokes (Phase 4) land there.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the radial wheel centered at the cursor and tracks cursor *direction* to
/// highlight a slice. `hide()` returns the slice that was selected on release.
@MainActor
final class OverlayWindowController {
    private static let log = Logger(subsystem: "com.zkwokleung.shortcutwheel", category: "overlay")

    private let viewModel = WheelViewModel()
    private var panel: OverlayPanel?
    private var displayLink: CADisplayLink?
    private var linkProxy: DisplayLinkProxy?

    /// Resolves a sub-wheel's id to its `Wheel`. Injected by the app (backed by
    /// `ConfigStore`) so the overlay needn't depend on the store.
    var wheelProvider: ((UUID) -> Wheel?)?

    /// How the cursor maps to a slice; set by the app before each `show`. In
    /// `precisePosition` the cursor must stay within `outerRadius` to select.
    var selectionMode: SelectionMode = .direction

    /// Mirrors `WheelView.outerRadius`; the bound used to gate selection in
    /// precise-position mode. (Radii are kept per-view in this codebase.)
    private let outerRadius: CGFloat = 132

    /// Slots of the wheel currently shown, parallel to `viewModel.slices` (`nil` =
    /// empty slot), kept so `hide()` can return the model `WheelSlice` picked.
    private var currentSlices: [WheelSlice?] = []

    /// Navigation stack of wheels; the last entry is what's on screen. Root at [0].
    private var wheelStack: [Wheel] = []

    /// Cursor rest time, in seconds, before drilling into / out of a sub-wheel.
    private let dwellThreshold: CFTimeInterval = 0.35
    /// Monotonic timestamp (CACurrentMediaTime) the current dwell started, if any.
    private var dwellAnchor: CFTimeInterval?
    /// True once a dwell has fired its action; blocks re-firing until the cursor
    /// moves to a different slice. Prevents a single rest from cascading through
    /// nested wheels and stops a dead-end sub-wheel pinning the ring.
    private var dwellConsumed = false
    /// Cap stack growth; with the cycle guard this also bounds auto-advance.
    private let maxDepth = 8

    /// Wheel center in screen space (y-up), snapshotted at show time.
    private var center: CGPoint = .zero
    private let panelSize = CGSize(width: 340, height: 340)

    var isVisible: Bool { panel != nil }

    func show(rootWheel: Wheel, at anchor: CGPoint? = nil) {
        // Nothing to show if every slot is empty.
        guard panel == nil, rootWheel.slices.contains(where: { $0 != nil }) else { return }
        wheelStack = [rootWheel]
        present(rootWheel)
        resetDwell()

        // Anchor at the caller's point (the press point in drag-to-open mode) or, by
        // default, the current cursor.
        center = anchor ?? NSEvent.mouseLocation

        let panel = OverlayPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: WheelView(model: viewModel))
        host.frame = CGRect(origin: .zero, size: panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        panel.setFrameOrigin(CGPoint(x: center.x - panelSize.width / 2,
                                     y: center.y - panelSize.height / 2))
        panel.orderFrontRegardless()
        self.panel = panel

        startTracking(host: host)
    }

    /// Swaps the displayed wheel in place without moving the panel — used for
    /// sub-wheel navigation as well as the initial `show`. Does not touch dwell
    /// state; `handleTick` owns that (so a swap can't masquerade as a cursor move).
    private func present(_ wheel: Wheel) {
        currentSlices = wheel.slices
        viewModel.slices = wheel.slices.enumerated().map { index, slice in
            guard let slice else {
                return SliceDisplay(id: index, label: "", symbol: nil, tint: .gray, isSubWheel: false, isEmpty: true)
            }
            return SliceDisplay(
                id: index,
                label: slice.label,
                symbol: slice.symbol,
                tint: Color(hex: slice.tintHex),
                isSubWheel: slice.action.isSubWheel,
                isEmpty: false
            )
        }
        viewModel.canGoBack = wheelStack.count > 1
    }

    private func resetDwell() {
        viewModel.selectedIndex = nil
        viewModel.dwellProgress = 0
        viewModel.canGoBack = false
        dwellAnchor = nil
        dwellConsumed = false
    }

    /// Hides the wheel and returns the slice selected on release (`nil` if the
    /// wheel wasn't showing or the cursor was in the cancel/dead zone).
    @discardableResult
    func hide() -> WheelSlice? {
        guard panel != nil else { return nil }
        // Stop ticks before reading so a late tick can't change the result.
        stopTracking()
        let selected = viewModel.selectedIndex.flatMap { index in
            currentSlices.indices.contains(index) ? currentSlices[index] : nil
        }
        resetDwell()
        currentSlices = []
        wheelStack = []
        panel?.orderOut(nil)
        panel = nil
        return selected
    }

    private func startTracking(host: NSView) {
        let proxy = DisplayLinkProxy()
        proxy.controller = self
        let link = host.displayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        linkProxy = proxy
        displayLink = link
    }

    private func stopTracking() {
        displayLink?.invalidate()
        displayLink = nil
        linkProxy = nil
    }

    fileprivate func handleTick() {
        let now = CACurrentMediaTime()
        // Sample the cursor once per tick: reusing it for both the selection calc
        // and the post-fire re-anchor avoids two reads disagreeing on a slice
        // boundary (which could leak an extra drill).
        let cursor = NSEvent.mouseLocation
        let maxRadius: CGFloat? = selectionMode == .precisePosition ? outerRadius : nil
        let index = WheelGeometry.sliceIndex(
            forCursor: cursor,
            center: center,
            sliceCount: viewModel.slices.count,
            maxRadius: maxRadius
        )

        // A genuine change of pointed slice starts a fresh dwell and re-arms.
        if index != viewModel.selectedIndex {
            viewModel.selectedIndex = index
            dwellAnchor = now
            dwellConsumed = false
            viewModel.dwellProgress = 0
        }

        // Dwell drills into a sub-wheel slice, or (when nested) backs out via center.
        let entering = index.map { isSubWheel($0) } ?? false
        let backing = index == nil && wheelStack.count > 1
        guard (entering || backing), !dwellConsumed, let anchor = dwellAnchor else {
            viewModel.dwellProgress = 0
            return
        }

        let progress = min(1, max(0, now - anchor) / dwellThreshold)
        viewModel.dwellProgress = progress
        guard progress >= 1 else { return }

        // Fire once. Mark consumed so a motionless cursor can't cascade through
        // nested wheels (or re-fire on a dead-end); a different slice re-arms it.
        dwellConsumed = true
        viewModel.dwellProgress = 0
        if entering, let i = index, let id = currentSlices[i]?.action.subWheelID {
            navigate(toSubWheel: id) // result intentionally ignored: a failed/no-op
                                     // drill stays consumed (no retry storm).
        } else if backing {
            navigateBack()
        }
        // Re-anchor selection to the slice under the *same* cursor sample in the
        // (possibly new) wheel, so the consumed state holds until the cursor moves.
        viewModel.selectedIndex = WheelGeometry.sliceIndex(
            forCursor: cursor,
            center: center,
            sliceCount: viewModel.slices.count,
            maxRadius: maxRadius
        )
    }

    private func isSubWheel(_ index: Int) -> Bool {
        currentSlices.indices.contains(index) && (currentSlices[index]?.action.isSubWheel ?? false)
    }

    @discardableResult
    private func navigate(toSubWheel id: UUID) -> Bool {
        // Guard against cyclic configs (A→B→A) and runaway depth, either of which
        // would otherwise grow the stack without bound while the cursor rests.
        guard wheelStack.count < maxDepth,
              !wheelStack.contains(where: { $0.id == id }),
              let child = wheelProvider?(id),
              child.slices.contains(where: { $0 != nil }) else {
            Self.log.notice("Sub-wheel navigation skipped (missing/empty/cyclic/too deep)")
            return false
        }
        wheelStack.append(child)
        present(child)
        return true
    }

    private func navigateBack() {
        guard wheelStack.count > 1 else { return }
        wheelStack.removeLast()
        present(wheelStack[wheelStack.count - 1])
    }
}

/// Breaks the `CADisplayLink` → target retain cycle: the link retains this proxy,
/// but the proxy references the controller weakly, so the controller can be freed.
private final class DisplayLinkProxy {
    weak var controller: OverlayWindowController?

    @objc func tick() {
        MainActor.assumeIsolated { controller?.handleTick() }
    }
}
