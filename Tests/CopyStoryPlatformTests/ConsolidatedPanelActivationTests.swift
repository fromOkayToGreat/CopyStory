import Foundation
import Testing
@testable import CopyStory

@Suite(.serialized) @MainActor struct ConsolidatedPanelActivationTests {
    @MainActor final class Harness {
        var now: TimeInterval = 0
        var active = false
        var tracking = false
        var valid = true
        var visible = false
        var verifyPresentation = true
        var activationCalls = 0
        var presentCalls = 0
        var hideCalls = 0
        var outcomes: [PanelActivationGate.Result] = []
        var callbacks: [Int: @MainActor () -> Void] = [:]
        var cancelled: Set<Int> = []
        var intervals: [TimeInterval] = []
        var onPresent: (() -> Void)?
        var onActivate: (() -> Void)?
        var nextTimer = 0
        var diagnosticRecords: [HistoryPresentationDiagnostics.Record] = []
        var diagnosticClockCalls = 0
        var recordDiagnostics = false
        lazy var diagnostics = HistoryPresentationDiagnostics(now: {
            self.diagnosticClockCalls += 1; return self.now
        }, sink: recordDiagnostics ? { self.diagnosticRecords.append($0) } : nil)
        lazy var gate = PanelActivationGate(environment: environment, diagnostics: diagnostics)
        var environment: PanelActivationEnvironment {
            PanelActivationEnvironment(now: { self.now }, isActive: { self.active },
                isTrackingMenu: { self.tracking }, requestActivation: { self.activationCalls += 1; self.onActivate?() },
                present: {
                    self.presentCalls += 1; self.visible = true
                    self.onPresent?(); return self.verifyPresentation
                }, hide: { self.hideCalls += 1; self.visible = false },
                scheduleTimeout: { interval, action in
                    self.nextTimer += 1; let id = self.nextTimer
                    self.callbacks[id] = action; self.intervals.append(interval)
                    return { self.cancelled.insert(id) }
                })
        }
        func begin() { gate.begin(valid: { self.valid }, completion: { self.outcomes.append($0) }) }
        func fire(_ id: Int) { callbacks[id]?() } // also simulate a queued, cancelled callback.
    }
    @Test func initiallyActivePresentsWithoutActivationRequest() {
        let h = Harness(); h.active = true; h.begin()
        #expect(h.activationCalls == 0 && h.presentCalls == 1 && h.visible)
        #expect(h.outcomes == [.presented] && !h.gate.isPending && h.cancelled.contains(1))
    }
    @Test func delayedAcknowledgementRequiresActualActiveState() {
        let h = Harness(); h.begin()
        #expect(h.presentCalls == 0 && h.activationCalls == 1)
        h.now = 0.2; h.gate.activationOrMenuChanged()
        #expect(h.presentCalls == 0) // Notification by itself is not active-state proof.
        h.now = 0.4; h.active = true; h.gate.activationOrMenuChanged()
        #expect(h.outcomes == [.presented] && h.presentCalls == 1)
    }
    @Test func exactDeadlineTimesOutAndLateActivationCannotPresent() {
        let h = Harness(); h.begin(); h.now = 2; h.fire(1)
        #expect(h.outcomes == [.timedOut] && h.presentCalls == 0 && !h.gate.isPending)
        h.active = true; h.now = 2.1; h.gate.activationOrMenuChanged(); h.fire(1)
        #expect(h.presentCalls == 0 && h.outcomes == [.timedOut])
    }
    @Test func earlyTimerRearmsRemainingBudgetWithoutExtension() {
        let h = Harness(); h.begin(); h.now = 1.5; h.fire(1)
        #expect(h.intervals == [2, 0.5] && h.gate.isPending)
        h.now = 2; h.active = true; h.fire(2)
        #expect(h.outcomes == [.timedOut] && h.presentCalls == 0)
    }
    @Test func cancellationDefeatsQueuedTimerAndActivation() {
        let h = Harness(); h.begin(); h.gate.cancel()
        h.active = true; h.now = 0.5; h.fire(1); h.gate.activationOrMenuChanged()
        #expect(h.outcomes == [.cancelled] && h.presentCalls == 0 && !h.visible)
    }
    @Test func replacedRequestIgnoresOldTimer() {
        let h = Harness(); h.begin(); h.now = 0.4; h.begin()
        #expect(h.outcomes == [.cancelled])
        h.now = 2; h.fire(1)
        #expect(h.gate.isPending && h.presentCalls == 0)
        h.active = true; h.gate.activationOrMenuChanged()
        #expect(h.outcomes == [.cancelled, .presented] && h.presentCalls == 1)
    }
    @Test func invalidRequestCannotActivateOrPresent() {
        let h = Harness(); h.valid = false; h.begin()
        #expect(h.outcomes == [.invalidRequest] && h.activationCalls == 0 && h.presentCalls == 0)
    }
    @Test func invalidationWhilePendingCannotPresent() {
        let h = Harness(); h.begin(); h.valid = false; h.active = true; h.gate.activationOrMenuChanged()
        #expect(h.outcomes == [.invalidRequest] && h.presentCalls == 0)
    }
    @Test func menuTrackingDefersPresentationUntilEndWithinSameDeadline() {
        let h = Harness(); h.tracking = true; h.active = true; h.begin()
        #expect(h.presentCalls == 0)
        h.now = 1; h.tracking = false; h.gate.activationOrMenuChanged()
        #expect(h.outcomes == [.presented] && h.presentCalls == 1)
    }
    @Test func menuNeverFinishesCannotPresentAfterDeadline() {
        let h = Harness(); h.tracking = true; h.active = true; h.begin()
        h.now = 2; h.fire(1); h.tracking = false; h.gate.activationOrMenuChanged()
        #expect(h.outcomes == [.timedOut] && h.presentCalls == 0)
    }
    @Test func unverifiedPanelOrLostActivationHidesWithoutSuccess() {
        let a = Harness(); a.active = true; a.verifyPresentation = false; a.begin()
        #expect(a.outcomes == [.presentationUnverified] && !a.visible)
        let b = Harness(); b.active = true; b.onPresent = { b.active = false }; b.begin()
        #expect(b.outcomes == [.presentationUnverified] && !b.visible)
    }
    @Test func presentReturningAfterDeadlineIsNotAccepted() {
        let h = Harness(); h.active = true; h.onPresent = { h.now = 2 }; h.begin()
        #expect(h.outcomes == [.presentationUnverified] && !h.visible)
    }
    @Test func reentrantCloseDuringNativeOrderingCannotReportOrLeavePresentation() {
        let h = Harness(); h.active = true; h.onPresent = { h.gate.cancel() }; h.begin()
        #expect(h.outcomes == [.cancelled] && !h.visible && !h.gate.isPending)
    }
    @Test func reentrantActivationAcknowledgementDoesNotPresentTwiceOrHideSuccess() {
        let h = Harness(); h.active = true
        h.onPresent = { h.gate.activationOrMenuChanged() }
        h.begin()
        #expect(h.outcomes == [.presented] && h.presentCalls == 1 && h.visible && h.hideCalls == 0)
    }
    @Test func reentrantNewGenerationCannotBeHiddenByOldCleanup() {
        let h = Harness(); h.active = true
        h.onPresent = { h.onPresent = nil; h.begin() }
        h.begin()
        #expect(h.outcomes == [.cancelled, .presented] && h.presentCalls == 2 && h.visible)
        #expect(h.hideCalls == 1) // Cancellation hid old request; old return did not hide new success.
    }
    @Test func invalidAndBackwardsClockFailClosed() {
        let a = Harness(); a.now = .nan; a.begin()
        #expect(a.outcomes == [.invalidClock] && a.presentCalls == 0)
        let b = Harness(); b.now = 3; b.begin(); b.now = 2; b.active = true; b.gate.activationOrMenuChanged()
        #expect(b.outcomes == [.invalidClock] && b.presentCalls == 0)
    }
    @Test func newOwnedFailuresAlwaysHideUnverifiedVisibility() {
        let timeout = Harness(); timeout.visible = true; timeout.begin(); timeout.now = 2; timeout.fire(1)
        #expect(timeout.outcomes == [.timedOut] && !timeout.visible)
        let invalid = Harness(); invalid.visible = true; invalid.valid = false; invalid.begin()
        #expect(invalid.outcomes == [.invalidRequest] && !invalid.visible)
        let clock = Harness(); clock.visible = true; clock.now = .nan; clock.begin()
        #expect(clock.outcomes == [.invalidClock] && !clock.visible)
    }
    @Test func focusExistingInvalidClockAndCancellationCannotHideExistingPanel() {
        let invalid = Harness(); invalid.visible = true; invalid.now = .nan
        invalid.gate.begin(valid: { true }, preservingExistingPresentation: true, completion: { invalid.outcomes.append($0) })
        #expect(invalid.outcomes == [.invalidClock] && invalid.visible)
        let cancelled = Harness(); cancelled.visible = true
        cancelled.gate.begin(valid: { true }, preservingExistingPresentation: true, completion: { cancelled.outcomes.append($0) })
        cancelled.gate.cancel()
        #expect(cancelled.outcomes == [.cancelled] && cancelled.visible && cancelled.presentCalls == 0)
    }
    @Test(arguments: ["presented", "timedOut", "invalidRequest", "invalidClock", "presentationUnverified", "cancelled", "reentrant", "replacement", "menu"])
    func diagnosticsPreserveEffectsAndResults(scenario: String) {
        func run(_ h: Harness) {
            switch scenario {
            case "presented": h.active = true; h.begin()
            case "timedOut": h.begin(); h.now = 2; h.fire(1)
            case "invalidRequest": h.valid = false; h.begin()
            case "invalidClock": h.now = .nan; h.begin()
            case "presentationUnverified": h.active = true; h.verifyPresentation = false; h.begin()
            case "cancelled": h.begin(); h.gate.cancel(); h.fire(1)
            case "reentrant": h.active = true; h.onPresent = { h.gate.cancel() }; h.begin()
            case "replacement": h.active = true; h.onPresent = { h.onPresent = nil; h.begin() }; h.begin()
            default: h.active = true; h.tracking = true; h.begin(); h.now = 1; h.tracking = false; h.gate.activationOrMenuChanged()
            }
        }
        let inert = Harness(), recording = Harness(); recording.recordDiagnostics = true
        run(inert); run(recording)
        #expect(inert.outcomes == recording.outcomes)
        #expect(inert.activationCalls == recording.activationCalls && inert.presentCalls == recording.presentCalls)
        #expect(inert.hideCalls == recording.hideCalls && inert.visible == recording.visible)
        #expect(inert.intervals == recording.intervals && inert.cancelled == recording.cancelled)
        #expect(inert.gate.isPending == recording.gate.isPending && inert.diagnosticClockCalls == 0)
        let reasons = recording.diagnosticRecords.filter { $0.event == .gateResult }.map { $0.reason.rawValue }
        #expect(reasons == recording.outcomes.map { $0.rawValue })
        #expect(!recording.diagnosticRecords.isEmpty)
    }
    @Test func diagnosticSchemaContainsOnlyAllowlistedMetadataAndRelativeTime() {
        var records: [HistoryPresentationDiagnostics.Record] = []
        var now = 50.0
        let diagnostics = HistoryPresentationDiagnostics(now: { now }, sink: { records.append($0) })
        for event in HistoryPresentationDiagnostics.Event.allCases {
            for reason in HistoryPresentationDiagnostics.Reason.allCases { diagnostics.emit(event, reason) }
        }
        now = 50.25; diagnostics.emit(.orderFrontAfter, active: true, visible: true, key: true)
        #expect(records.first?.elapsed == 0 && records.last?.elapsed == 0.25)
        #expect(records.first?.active == nil && records.first?.line.contains("active=unsampled") == true)
        #expect(records.map(\.sequence) == Array(1...UInt64(records.count)))
        let fields: Set<String> = ["event", "reason", "elapsed", "sequence", "requestGeneration", "active", "visible", "key", "pending", "menuDepth", "presentationOwned", "menuOwned", "ticketMatches", "generationMatches", "valid"]
        for record in records {
            let keys = Set(record.line.split(separator: " ").map { String($0.split(separator: "=")[0]) })
            #expect(keys == fields)
            #expect(!record.line.contains("/") && !record.line.contains("Synthetic secret"))
        }
        now = .nan; diagnostics.emit(.gateResult, .invalidClock)
        #expect(records.last?.elapsed == 0)
    }

}
