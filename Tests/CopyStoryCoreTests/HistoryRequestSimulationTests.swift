import Testing
@testable import CopyStoryCore

@Suite struct HistoryRequestSimulationTests {
    typealias Model = HistoryRequestSimulation
    let target = Model.Identity(pid: 42, bundleID: "synthetic.target", bundlePath: "/synthetic/target", launchTime: 1)
    let text = HistoryRecordingSinks.Payload.text("Synthetic café 🧪\nline\tend  ")
    final class Fixture {
        let sinks = HistoryRecordingSinks()
        var state: Model.Snapshot
        var onSnapshot: (() -> Void)?
        lazy var model = Model(ownPID: 1, sinks: sinks, snapshot: { [unowned self] in
            let result = Model.Snapshot(now: self.state.now, frontmost: self.state.frontmost,
                destinationAlive: self.state.destinationAlive, permission: self.state.permission,
                modifiersReleased: self.state.modifiersReleased, boardVersion: self.sinks.boardVersion)
            self.onSnapshot?()
            return result
        })
        init(_ target: Model.Identity) { state = Model.Snapshot(now: 1, frontmost: target) }
    }
    func prepare(_ f: Fixture) -> Model.Ticket? {
        if case .pending(let ticket) = f.model.handle(.paste, payload: text) { return ticket }
        Issue.record("Expected one pending synthetic request"); return nil
    }
    @Test func passiveActionsAndOpenHaveNoSideEffects() {
        let f = Fixture(target); f.model.open(identity: target, now: 0)
        for action: Model.Action in [.selection, .search, .edit] {
            #expect(f.model.handle(action, payload: text) == .ignored)
        }
        #expect(f.sinks.records.isEmpty); #expect(f.model.feedback == .idle)
    }
    @Test func copyIsExplicitAndNeverSchedulesEventOrAdmission() {
        let f = Fixture(target); f.state.permission = .denied
        #expect(f.model.handle(.copy, payload: text) == .recordedCopy)
        #expect(f.sinks.records == [.writeAttempt(0, text), .writeSucceeded(0, 1)])
        #expect(f.model.feedback == .copyRecorded)
        #expect(f.model.feedback.text.contains("No real clipboard"))
    }
    @Test func successRecordsWriteAdmissionDismissalThenOneFrozenPair() throws {
        let f = Fixture(target); let t = f.model.open(identity: target, now: 0)
        #expect(prepare(f) == t)
        #expect(f.sinks.records == [.writeAttempt(t.generation, text), .writeSucceeded(t.generation, 1),
            .admissionOpportunity(t.generation), .dismissalIntent(t.generation)])
        #expect(f.model.handle(.paste, payload: .text("duplicate")) == .rejected(.consumed))
        #expect(f.model.finish(t) == .recordedPair)
        #expect(Array(f.sinks.records.suffix(2)) == [.eventIntent(t.generation, target, .down), .eventIntent(t.generation, target, .up)])
        let count = f.sinks.records.count
        #expect(f.model.finish(t) == .rejected(.consumed)); #expect(f.sinks.records.count == count)
        #expect(f.model.feedback == .pairRecorded)
        #expect(f.model.feedback.text.contains("no real paste or insertion is confirmed"))
    }
    @Test func imageBytesAreOpaqueAndFrozen() {
        let f = Fixture(target); let t = f.model.open(identity: target, now: 0)
        let image = HistoryRecordingSinks.Payload.image([0, 255, 128, 0])
        #expect(f.model.handle(.paste, payload: image) == .pending(t))
        #expect(f.sinks.records.first == .writeAttempt(t.generation, image))
    }
    @Test func everyCancellationBeforeWriteIsSticky() {
        for reason: Model.Cancellation in [.explicit, .activation, .termination, .space, .sleep, .selection] {
            let f = Fixture(target); let t = f.model.open(identity: target, now: 0)
            f.model.cancel(reason, ticket: t); f.model.applicationActivated(target, ticket: t)
            #expect(f.model.handle(.paste, payload: text) == .rejected(.cancelled))
            #expect(f.sinks.records.isEmpty)
            #expect(f.model.handle(.paste, payload: text) == .rejected(.consumed))
        }
    }
    @Test func unavailableOrOwnIdentityNeverWrites() {
        for identity in [nil, Model.Identity(pid: 1, bundleID: "own", bundlePath: "/own", launchTime: 1)] {
            let f = Fixture(target); f.model.open(identity: identity, now: 0)
            #expect(f.model.handle(.paste, payload: text) == .rejected(.destinationUnavailable))
            #expect(f.sinks.records.isEmpty)
        }
    }
    @Test func eachPrewriteFailureRejectsWithoutAnyRecordingOrRetry() {
        for failure in 0..<7 {
            let f = Fixture(target); f.model.open(identity: target, now: 0)
            switch failure {
            case 0: f.state.now = 30
            case 1: f.state.now = -1
            case 2: f.state.frontmost = nil
            case 3: f.state.destinationAlive = false
            case 4: f.state.permission = .denied
            case 5: f.state.permission = .unknown
            default: f.state.modifiersReleased = false
            }
            if case .rejected = f.model.handle(.paste, payload: text) {} else { Issue.record("Unsafe prewrite state accepted") }
            #expect(f.sinks.records.isEmpty)
            f.state = Model.Snapshot(now: 1, frontmost: target)
            #expect(f.model.handle(.paste, payload: text) == .rejected(.consumed))
        }
    }
    @Test func failedWriteNeverAdmitsDismissesOrSchedulesPair() {
        let f = Fixture(target); let t = f.model.open(identity: target, now: 0); f.sinks.writesSucceed = false
        #expect(f.model.handle(.paste, payload: text) == .rejected(.writeFailed))
        #expect(f.sinks.records == [.writeAttempt(t.generation, text), .writeFailed(t.generation)])
        f.sinks.writesSucceed = true
        #expect(f.model.handle(.paste, payload: text) == .rejected(.consumed))
        #expect(f.model.finish(t) == .rejected(.consumed))
    }
    @Test func eachFinalFailureConsumesClaimAndPreservesSuccessfulWriteAdmissionOnly() throws {
        for failure in 0..<8 {
            let f = Fixture(target); f.model.open(identity: target, now: 0)
            let t = try #require(prepare(f)); let records = f.sinks.records
            switch failure {
            case 0: f.state.now = 30
            case 1: f.state.now = -1
            case 2: f.state.frontmost = nil
            case 3: f.state.destinationAlive = false
            case 4: f.state.permission = .denied
            case 5: f.state.permission = .unknown
            case 6: f.state.modifiersReleased = false
            default: f.sinks.replaceBoardForSimulation()
            }
            if case .rejected = f.model.finish(t) {} else { Issue.record("Unsafe final state accepted") }
            #expect(f.sinks.records == records)
            f.state = Model.Snapshot(now: 2, frontmost: target)
            #expect(f.model.finish(t) == .rejected(.consumed))
            #expect(f.model.handle(.paste, payload: text) == .rejected(.consumed))
        }
    }
    @Test func identityChangeWithSamePIDRejectsFinalPair() throws {
        for identity in [Model.Identity(pid: 42, bundleID: "other", bundlePath: target.bundlePath, launchTime: 1),
                         Model.Identity(pid: 42, bundleID: target.bundleID, bundlePath: "/other", launchTime: 1),
                         Model.Identity(pid: 42, bundleID: target.bundleID, bundlePath: target.bundlePath, launchTime: 2)] {
            let f = Fixture(target); f.model.open(identity: target, now: 0)
            let t = try #require(prepare(f)); f.state.frontmost = identity
            #expect(f.model.finish(t) == .rejected(.identityChanged)); #expect(f.sinks.records.count == 4)
        }
    }
    @Test func pendingSelectionAndAwayReturnStayCancelled() throws {
        for action: Model.Action in [.selection, .search, .edit] {
            let f = Fixture(target); f.model.open(identity: target, now: 0)
            let t = try #require(prepare(f)); _ = f.model.handle(action, payload: text)
            #expect(f.model.finish(t) == .rejected(.cancelled)); #expect(f.sinks.records.count == 4)
        }
        let f = Fixture(target); let t = f.model.open(identity: target, now: 0)
        _ = prepare(f); f.model.applicationActivated(nil, ticket: t); f.model.applicationActivated(target, ticket: t)
        #expect(f.model.finish(t) == .rejected(.cancelled))
    }
    @Test func staleCompletionAndCancellationDoNotTouchFreshRequest() throws {
        let f = Fixture(target); let old = f.model.open(identity: target, now: 0); _ = prepare(f)
        let fresh = f.model.open(identity: target, now: 1); _ = prepare(f)
        let records = f.sinks.records; let feedback = f.model.feedback
        f.model.cancel(.space, ticket: old)
        #expect(f.model.finish(old) == .stale)
        #expect(f.model.currentTicket == fresh); #expect(f.model.isPending)
        #expect(f.model.feedback == feedback); #expect(f.sinks.records == records)
        #expect(f.model.finish(fresh) == .recordedPair)
    }
    @Test func reentryDuringPrewriteCannotWriteOrMutateNewGeneration() {
        let f = Fixture(target); let old = f.model.open(identity: target, now: 0)
        f.onSnapshot = { f.onSnapshot = nil; _ = f.model.open(identity: self.target, now: 1) }
        #expect(f.model.handle(.paste, payload: text) == .stale)
        #expect(f.model.currentTicket != old); #expect(f.model.feedback == .idle); #expect(f.sinks.records.isEmpty)
        #expect(prepare(f) == f.model.currentTicket)
    }
    @Test func reentryDuringFinalClaimCannotConsumeNewGeneration() throws {
        let f = Fixture(target); f.model.open(identity: target, now: 0)
        let old = try #require(prepare(f))
        f.onSnapshot = { f.onSnapshot = nil; _ = f.model.open(identity: self.target, now: 1); _ = self.prepare(f) }
        #expect(f.model.finish(old) == .stale)
        #expect(f.model.isPending); #expect(f.model.feedback == .waiting)
        #expect(f.model.finish(f.model.currentTicket) == .recordedPair)
    }
    @Test func cancellationAndRepeatedFinishInsideFinalSnapshotClaimNeverRetry() throws {
        let f = Fixture(target); let t = f.model.open(identity: target, now: 0); _ = prepare(f)
        var nested: Model.Outcome?
        f.onSnapshot = { f.onSnapshot = nil; nested = f.model.finish(t); f.model.cancel(.space, ticket: t) }
        #expect(f.model.finish(t) == .rejected(.cancelled)); #expect(nested == .rejected(.consumed))
        #expect(f.sinks.records.count == 4)
    }
    @Test func explicitCopyAfterDeniedPasteDoesNotRecoverOrRetryPaste() {
        let f = Fixture(target); let t = f.model.open(identity: target, now: 0); f.state.permission = .denied
        #expect(f.model.handle(.paste, payload: text) == .rejected(.permissionDenied))
        #expect(f.model.feedback.text.contains("Explicit Copy is a separate action"))
        #expect(f.model.handle(.copy, payload: text) == .recordedCopy)
        f.state.permission = .available
        #expect(f.model.handle(.paste, payload: text) == .rejected(.consumed))
        #expect(f.model.finish(t) == .rejected(.consumed)); #expect(f.sinks.records.count == 2)
    }
    @Test func invalidClockAndIncompleteIdentityCannotWrite() {
        for now in [Double.nan, .infinity, -.infinity] {
            let f = Fixture(target); f.model.open(identity: target, now: 0); f.state.now = now
            #expect(f.model.handle(.paste, payload: text) == .rejected(.expired))
            #expect(f.sinks.records.isEmpty)
        }
        for identity in [Model.Identity(pid: 0, bundleID: "target", bundlePath: "/target", launchTime: 1),
                         Model.Identity(pid: 42, bundleID: "", bundlePath: "/target", launchTime: 1),
                         Model.Identity(pid: 42, bundleID: "target", bundlePath: "", launchTime: 1),
                         Model.Identity(pid: 42, bundleID: "target", bundlePath: "/target", launchTime: .nan)] {
            let f = Fixture(target); f.model.open(identity: identity, now: 0)
            #expect(f.model.handle(.paste, payload: text) == .rejected(.destinationUnavailable))
            #expect(f.sinks.records.isEmpty)
        }
    }
    @Test func staleSnapshotCharacterizesUnobservedExternalChangeWithoutClaimingAtomicity() throws {
        let f = Fixture(target); f.model.open(identity: target, now: 0); let t = try #require(prepare(f))
        // Provider returns an old available snapshot while external test state
        // changes. This intentionally demonstrates the snapshot limitation.
        f.onSnapshot = { f.onSnapshot = nil; f.state.permission = .denied; f.state.frontmost = nil }
        #expect(f.model.finish(t) == .recordedPair)
        #expect(Array(f.sinks.records.suffix(2)) == [.eventIntent(t.generation, target, .down), .eventIntent(t.generation, target, .up)])
        #expect(f.model.feedback == .pairRecorded) // simulation only, never a revocation pass
    }
}
