import Testing
@testable import ShortcutWheel

/// Truth table for `GlobalHotkeyMonitor.swallowAction` — the pure policy that decides
/// whether a matched trigger event is passed, swallowed, buffered, or replayed.
struct SwallowActionTests {
    private typealias Action = GlobalHotkeyMonitor.SwallowAction

    private func action(
        swallow: Bool = true,
        kind: TriggerBinding.Kind = .mouseButton,
        mode: TriggerBinding.ActivationMode,
        edge: GlobalHotkeyMonitor.Edge,
        wheelOpen: Bool = false
    ) -> Action {
        GlobalHotkeyMonitor.swallowAction(
            swallow: swallow, kind: kind, mode: mode, edge: edge, wheelOpen: wheelOpen
        )
    }

    @Test func nonSwallowingTriggerAlwaysPasses() {
        for mode in [TriggerBinding.ActivationMode.immediate, .holdDelay, .drag] {
            for edge in [GlobalHotkeyMonitor.Edge.down, .up, .repeatHold] {
                #expect(action(swallow: false, mode: mode, edge: edge) == .pass)
            }
        }
    }

    @Test func modifierIsNeverSwallowed() {
        // Swallowing a flagsChanged would corrupt global modifier state, so modifiers
        // pass through regardless of the toggle.
        for edge in [GlobalHotkeyMonitor.Edge.down, .up, .repeatHold] {
            #expect(action(kind: .modifier, mode: .holdDelay, edge: edge) == .pass)
        }
    }

    @Test func immediateModeSwallowsEveryEdge() {
        #expect(action(mode: .immediate, edge: .down) == .swallow)
        #expect(action(mode: .immediate, edge: .up, wheelOpen: true) == .swallow)
        #expect(action(mode: .immediate, edge: .repeatHold) == .swallow)
    }

    @Test func holdDelayBuffersPressAndDropsRepeats() {
        #expect(action(mode: .holdDelay, edge: .down) == .bufferAndSwallow)
        #expect(action(mode: .holdDelay, edge: .repeatHold) == .swallow)
    }

    @Test func dragBuffersPressAndDropsRepeats() {
        #expect(action(mode: .drag, edge: .down) == .bufferAndSwallow)
        #expect(action(mode: .drag, edge: .repeatHold) == .swallow)
    }

    @Test func releaseAfterWheelOpenedIsSwallowed() {
        // The press was already swallowed; swallowing the release keeps the app from
        // seeing a lone, unbalanced up.
        #expect(action(mode: .holdDelay, edge: .up, wheelOpen: true) == .swallow)
        #expect(action(mode: .drag, edge: .up, wheelOpen: true) == .swallow)
    }

    @Test func releaseWithoutOpeningReplaysTheTap() {
        #expect(action(mode: .holdDelay, edge: .up, wheelOpen: false) == .replayTapThenSwallow)
        #expect(action(mode: .drag, edge: .up, wheelOpen: false) == .replayTapThenSwallow)
    }
}

/// Truth table for `GlobalHotkeyMonitor.upDisposition` — how a release is handled once
/// the runtime facts (did we own the press, is there a buffer to replay) are known.
struct UpDispositionTests {
    private typealias Action = GlobalHotkeyMonitor.SwallowAction
    private typealias Disposition = GlobalHotkeyMonitor.Disposition

    private func disposition(_ action: Action, owned: Bool, hasBuffer: Bool) -> Disposition {
        GlobalHotkeyMonitor.upDisposition(action: action, owned: owned, hasBuffer: hasBuffer)
    }

    @Test func nonSwallowingReleaseAlwaysPasses() {
        for owned in [true, false] {
            for hasBuffer in [true, false] {
                #expect(disposition(.pass, owned: owned, hasBuffer: hasBuffer) == .pass)
            }
        }
    }

    @Test func swallowedReleaseIsSwallowed() {
        // Release after the wheel opened (.swallow): the app saw neither edge.
        #expect(disposition(.swallow, owned: true, hasBuffer: false) == .swallow)
        #expect(disposition(.bufferAndSwallow, owned: true, hasBuffer: true) == .swallow)
    }

    @Test func tapReplaysOnlyWhenOwnedAndBuffered() {
        #expect(disposition(.replayTapThenSwallow, owned: true, hasBuffer: true) == .replay)
    }

    @Test func tapWithoutBufferPassesThroughInsteadOfVanishing() {
        // Orphan up (never owned) or a buffer cleared by a mid-hold rebind: the release
        // must reach the app, not be swallowed.
        #expect(disposition(.replayTapThenSwallow, owned: false, hasBuffer: true) == .pass)
        #expect(disposition(.replayTapThenSwallow, owned: true, hasBuffer: false) == .pass)
        #expect(disposition(.replayTapThenSwallow, owned: false, hasBuffer: false) == .pass)
    }
}
