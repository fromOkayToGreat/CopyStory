import Testing
@testable import RoutingCore

@Suite struct EventDeliveryBoundaryTests {
    // Values stand in for external snapshots; no OS events or permissions.
    @Test func eachInvalidFinalSnapshotPostsNothing() {
        for invalid in 0..<5 {
            var gates = Array(repeating: true, count: 5)
            gates[invalid] = false // generation, alive, foreground, board, permission
            var posted: [EventDeliveryBoundary.Event] = []
            let sent = EventDeliveryBoundary.deliver(validate: { gates.allSatisfy { $0 } },
                                                     post: { posted.append($0) })
            #expect(!sent); #expect(posted.isEmpty)
        }
    }
    @Test func validBoundaryPostsDownThenUpExactlyOnce() {
        var trace: [String] = []
        #expect(EventDeliveryBoundary.deliver(validate: { trace.append("check"); return true },
            post: { trace.append($0 == .down ? "down" : "up") }))
        #expect(trace == ["check", "down", "up"])
    }
    @Test func externalChangeAfterSnapshotIsNotAtomic() {
        var externalIsSafe = true
        var deliveredWhileUnsafe: [EventDeliveryBoundary.Event] = []
        EventDeliveryBoundary.deliver(validate: {
            let sampled = externalIsSafe
            externalIsSafe = false // deterministic adversarial interleaving
            return sampled
        }, post: { if !externalIsSafe { deliveredWhileUnsafe.append($0) } })
        // Characterization of the remaining risk, NOT a safety acceptance pass.
        #expect(deliveredWhileUnsafe == [.down, .up])
    }
    @Test func changeBetweenDownAndUpDoesNotRetryOrSuppressRelease() {
        var externalIsSafe = true
        var posted: [EventDeliveryBoundary.Event] = []
        var upSawUnsafe = false
        EventDeliveryBoundary.deliver(validate: { externalIsSafe }, post: { event in
            posted.append(event)
            if event == .down { externalIsSafe = false }
            else { upSawUnsafe = !externalIsSafe }
        })
        #expect(posted == [.down, .up]); #expect(upSawUnsafe)
    }
}
