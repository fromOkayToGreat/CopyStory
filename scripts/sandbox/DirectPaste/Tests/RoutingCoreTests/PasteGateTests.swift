import Testing
@testable import RoutingCore

@Suite struct PasteGateTests {
    func outcome(_ edit: (inout PasteGate) -> Void = { _ in }, now: Double = 1,
                 front: Int32? = 42, alive: Bool = true, count: Int = 7,
                 permission: Bool = true, modifiers: Bool = true) -> PasteGate.Outcome {
        var gate = PasteGate(ownPID: 1); gate.open(destination: 42, now: 0)
        let token = gate.begin(writeCount: 7)!
        edit(&gate)
        return gate.consume(token: token, now: now, frontmost: front,
                            destinationAlive: alive, currentWrite: count,
                            permission: permission, modifiersReleased: modifiers)
    }
    @Test func deliberateActionDispatchesOnce() {
        var g = PasteGate(ownPID: 1); g.open(destination: 42, now: 0)
        let token = g.begin(writeCount: 7)!
        #expect(g.begin(writeCount: 8) == nil)
        #expect(g.consume(token: token, now: 1, frontmost: 42, destinationAlive: true,
                          currentWrite: 7, permission: true, modifiersReleased: true) == .dispatch)
        #expect(g.consume(token: token, now: 1, frontmost: 42, destinationAlive: true,
                          currentWrite: 7, permission: true, modifiersReleased: true) == .consumed)
    }
    @Test func cancellationIsStickyAcrossAwayAndBackSwitch() {
        #expect(outcome { $0.applicationActivated(99); $0.applicationActivated(42) } == .cancelled)
    }
    @Test func panelActivationIsNotDestinationRestoration() {
        #expect(outcome { $0.applicationActivated(1) } == .cancelled)
    }
    @Test func explicitCancelNeverDispatches() { #expect(outcome { $0.invalidate() } == .cancelled) }
    @Test func interveningCopyNeverDispatches() { #expect(outcome(count: 8) == .clipboardChanged) }
    @Test func revokedOrDeniedPermissionNeverDispatches() { #expect(outcome(permission: false) == .permissionDenied) }
    @Test func closedTargetNeverDispatches() { #expect(outcome(alive: false) == .destinationUnavailable) }
    @Test func finalForegroundCheckCatchesUnobservedSwitch() { #expect(outcome(front: 99) == .appChanged) }
    @Test func timeoutNeverDispatches() { #expect(outcome(now: 30) == .expired) }
    @Test func heldModifiersNeverDispatch() { #expect(outcome(modifiers: false) == .modifiersHeld) }
    @Test func newInvocationRejectsOldAsyncCompletion() {
        #expect(outcome { $0.open(destination: 99, now: 1) } == .consumed)
    }
    @Test func noDestinationAndOwnAppAreNeverInferredFromHistory() {
        for pid: Int32? in [nil, 1] {
            var g = PasteGate(ownPID: 1); g.open(destination: pid, now: 0)
            let t = g.begin(writeCount: 7)!
            #expect(g.consume(token: t, now: 1, frontmost: 1, destinationAlive: true,
                              currentWrite: 7, permission: true, modifiersReleased: true) == .destinationUnavailable)
        }
    }
    @Test func failedRequestCannotRetry() {
        var g = PasteGate(ownPID: 1); g.open(destination: 42, now: 0)
        let t = g.begin(writeCount: 7)!
        #expect(g.consume(token: t, now: 1, frontmost: 42, destinationAlive: true,
                          currentWrite: 7, permission: false, modifiersReleased: true) == .permissionDenied)
        #expect(g.begin(writeCount: 7) == nil)
    }
    @Test func staleCompletionDoesNotConsumeNewRequest() {
        var g = PasteGate(ownPID: 1); g.open(destination: 42, now: 0)
        let old = g.begin(writeCount: 7)!
        g.open(destination: 99, now: 1)
        let fresh = g.begin(writeCount: 8)!
        #expect(g.consume(token: old, now: 2, frontmost: 99, destinationAlive: true,
                          currentWrite: 8, permission: true, modifiersReleased: true) == .consumed)
        #expect(g.consume(token: fresh, now: 2, frontmost: 99, destinationAlive: true,
                          currentWrite: 8, permission: true, modifiersReleased: true) == .dispatch)
    }
    @Test func failureThenRecoveredConditionsStillCannotRetry() {
        for failure in 0..<6 {
            var g = PasteGate(ownPID: 1); g.open(destination: 42, now: 0)
            let t = g.begin(writeCount: 7)!
            let first = g.consume(token: t, now: failure == 0 ? 30 : 1,
                frontmost: failure == 1 ? 99 : 42, destinationAlive: failure != 2,
                currentWrite: failure == 3 ? 8 : 7, permission: failure != 4,
                modifiersReleased: failure != 5)
            #expect(first != .dispatch)
            #expect(g.consume(token: t, now: 2, frontmost: 42, destinationAlive: true,
                              currentWrite: 7, permission: true, modifiersReleased: true) == .consumed)
            #expect(g.begin(writeCount: 9) == nil)
        }
    }
    @Test func expiryBoundaryAndClockRegression() {
        #expect(outcome(now: 29.999) == .dispatch)
        #expect(outcome(now: 30) == .expired)
        #expect(outcome(now: -0.001) == .expired)
    }
    @Test func invalidationAfterClaimSurvivesTargetReturn() {
        var g = PasteGate(ownPID: 1); g.open(destination: 42, now: 0)
        let t = g.begin(writeCount: 7)!
        g.invalidate(); g.applicationActivated(42)
        #expect(g.consume(token: t, now: 1, frontmost: 42, destinationAlive: true,
                          currentWrite: 7, permission: true, modifiersReleased: true) == .cancelled)
    }

}
