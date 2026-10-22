import Testing
@testable import CopyStoryCore

struct NativeLifecycleEffectsTests {
    typealias Request = HistoryRequestSimulation
    let target = Request.Identity(pid: 42, bundleID: "synthetic.target", bundlePath: "/synthetic/target", launchTime: 1)
    let own = Request.Identity(pid: 1, bundleID: "synthetic.own", bundlePath: "/synthetic/own", launchTime: 1)
    @Test func ownedPresentationIsAllowedOnlyBeforeWriteNeverAtFinalClaim() {
        let sinks = HistoryRecordingSinks()
        var front: Request.Identity? = own
        let request = Request(ownPID: 1, sinks: sinks, snapshot: {
            .init(now: 1, frontmost: front, boardVersion: sinks.boardVersion, presentationOwnsFocus: true)
        })
        let ticket = request.open(identity: target, now: 0)
        #expect(request.handle(.paste, payload: .text("synthetic")) == .pending(ticket))
        #expect(request.finish(ticket) == .rejected(.identityChanged))
        let next = request.open(identity: target, now: 0)
        #expect(request.handle(.paste, payload: .text("synthetic")) == .pending(next))
        front = target
        #expect(request.finish(next) == .recordedPair)
    }
    @Test func injectedWriteAndFinalEffectsCannotReenterIntoDuplicateCopyOrStaleFeedback() {
        var request: Request!
        var writes = 0, pairs = 0, version = 0
        request = Request(ownPID: 1, effects: .init(write: { _, _ in
            writes += 1; version += 1
            #expect(request.handle(.copy, payload: .text("nested")) == .ignored)
            return version
        }, pair: { _, _ in
            pairs += 1
            request.open(identity: target, now: 1)
            return .requested
        }), snapshot: { .init(now: 1, frontmost: target, boardVersion: version) })
        request.open(identity: target, now: 0)
        #expect(request.handle(.copy, payload: .text("copy")) == .recordedCopy)
        #expect(writes == 1)
        let ticket = request.currentTicket
        #expect(request.handle(.paste, payload: .text("paste")) == .pending(ticket))
        #expect(request.finish(ticket) == .stale)
        #expect(writes == 2 && pairs == 1 && request.feedback == .idle)
    }
}
