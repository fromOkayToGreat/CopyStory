import Foundation
import Testing
import CopyStoryCore
@testable import CopyStory

@Suite(.serialized) @MainActor
struct HistoryInvocationPathTests {
    typealias Fixture = HistoryRequestPathTests.Fixture
    typealias Gate = HistoryRequestPathTests.Gate
    func until(_ predicate: () -> Bool) async throws { try await HistoryRequestPathTests().until(predicate) }
    func finished(_ model: AppModel) async { await model.historyPasteTask?.value }

    @Test func existingToggleAndCoordinatorCaptureCreateFreshTicketWithoutUI() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(openCapture: false)
        #expect(f.requests.currentTicket.generation == 0)
        let delegate = AppDelegate(historyRecordingModel: f.model)
        delegate.toggleHistory()
        #expect(delegate.recordingHistoryVisible)
        #expect(f.requests.currentTicket.generation == 1); #expect(f.sinks.records.isEmpty)
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.successfulWrites.count == 1); #expect(f.sinks.records.count == 5)
        delegate.closeHistory(); #expect(!delegate.recordingHistoryVisible)
        delegate.toggleHistory(); #expect(f.requests.currentTicket.generation == 2)
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.successfulWrites.count == 2); #expect(f.sinks.records.count == 10)
    }
    @Test func coordinatorEntryPointUsesInjectedObservationAndNeverLiveFocus() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(openCapture: false)
        f.snapshot.frontmost = nil
        f.model.pasteCoordinator.rememberDestination()
        #expect(f.requests.currentTicket.generation == 1)
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.sinks.records.isEmpty)
        #expect(f.model.statusMessage?.contains("destinationUnavailable") == true)
    }
    @Test func closeBeforePasteInvalidatesEvenWithoutPendingTask() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(openCapture: false)
        let delegate = AppDelegate(historyRecordingModel: f.model)
        delegate.toggleHistory(); delegate.closeHistory()
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.sinks.records.isEmpty); #expect(f.model.statusMessage?.contains("cancelled") == true)
    }
    @Test func toggleDismissalDuringPayloadLoadStopsWriteAndOldCleanup() async throws {
        let gate = Gate(); var loads = 0
        let f = try Fixture(loader: { _ in
            loads += 1
            if loads == 1 { await gate.wait() }
            return CapturePayload(text: "Synthetic invocation \(loads)")
        })
        defer { gate.release(); f.clean() }; try await f.seed(openCapture: false)
        let delegate = AppDelegate(historyRecordingModel: f.model)
        delegate.toggleHistory(); f.model.pasteSelected(); let oldTask = f.model.historyPasteTask
        try await until { gate.entered }
        delegate.toggleHistory(); #expect(!f.model.busy)
        delegate.toggleHistory(); f.model.pasteSelected(); let newTask = f.model.historyPasteTask
        await newTask?.value; let feedback = f.model.statusMessage
        gate.release(); await oldTask?.value
        #expect(f.successfulWrites.count == 1); #expect(f.sinks.records.count == 5)
        #expect(f.model.statusMessage == feedback); #expect(!f.model.busy)
    }
    @Test func activationAwayAndReturnThroughDelegateIsStickyBeforeWrite() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(openCapture: false)
        let delegate = AppDelegate(historyRecordingModel: f.model); delegate.toggleHistory()
        delegate.observeHistoryRecording(.activated(nil))
        delegate.observeHistoryRecording(.activated(f.identity))
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.sinks.records.isEmpty); #expect(f.model.statusMessage?.contains("cancelled") == true)
    }
    @Test func spaceTerminationAndSleepCancelPendingFinalWorkThroughAppModel() async throws {
        for kind in 0..<3 {
            let gate = Gate(); let f = try Fixture(beforeFinish: { await gate.wait() })
            defer { gate.release(); f.clean() }; try await f.seed(openCapture: false)
            let delegate = AppDelegate(historyRecordingModel: f.model); delegate.toggleHistory()
            f.model.pasteSelected(); let task = f.model.historyPasteTask
            try await until { gate.entered }
            switch kind {
            case 0: delegate.observeHistoryRecording(.spaceChanged)
            case 1: delegate.observeHistoryRecording(.terminated(f.identity))
            default: delegate.observeHistoryRecording(.sleep)
            }
            #expect(!f.model.busy); gate.release(); await task?.value
            #expect(f.successfulWrites.count == 1); #expect(f.sinks.records.count == 3)
            #expect(f.model.statusMessage == nil)
        }
    }
    @Test func staleObservationCannotCancelFreshCaptureOrRequest() async throws {
        let gate = Gate(); let f = try Fixture(beforeFinish: { await gate.wait() })
        defer { gate.release(); f.clean() }; try await f.seed(openCapture: false)
        let delegate = AppDelegate(historyRecordingModel: f.model); delegate.toggleHistory()
        let old = f.requests.currentTicket
        delegate.closeHistory(); delegate.toggleHistory()
        f.model.pasteSelected(); let task = f.model.historyPasteTask; try await until { gate.entered }
        delegate.observeHistoryRecording(.spaceChanged, ticket: old)
        delegate.observeHistoryRecording(.stopped, ticket: old)
        #expect(delegate.recordingHistoryVisible); #expect(f.model.canRecordHistoryInvocation)
        #expect(f.model.busy); #expect(f.requests.feedback == .waiting)
        gate.release(); await task?.value
        #expect(f.sinks.records.count == 5)
    }
    @Test func unrelatedTerminationAndSameTargetActivationDoNotCancel() async throws {
        let gate = Gate(); let f = try Fixture(beforeFinish: { await gate.wait() })
        defer { gate.release(); f.clean() }; try await f.seed(openCapture: false)
        let delegate = AppDelegate(historyRecordingModel: f.model); delegate.toggleHistory()
        f.model.pasteSelected(); let task = f.model.historyPasteTask; try await until { gate.entered }
        let other = HistoryRequestSimulation.Identity(pid: 42, bundleID: f.identity.bundleID,
            bundlePath: f.identity.bundlePath, launchTime: 99)
        delegate.observeHistoryRecording(.terminated(other))
        delegate.observeHistoryRecording(.activated(f.identity))
        #expect(f.model.busy); gate.release(); await task?.value
        #expect(f.sinks.records.count == 5)
    }
    @Test func existingResignActiveEntryCancelsWithoutPanelOrApplication() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(openCapture: false)
        let delegate = AppDelegate(historyRecordingModel: f.model); delegate.toggleHistory()
        delegate.applicationDidResignActive(Notification(name: Notification.Name("synthetic.resign")))
        #expect(!delegate.recordingHistoryVisible)
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.sinks.records.isEmpty)
    }
    @Test func stopCancelsOwnershipAndBlocksSubsequentRecordingAndNativeSetup() async throws {
        let gate = Gate(); let f = try Fixture(beforeFinish: { await gate.wait() })
        defer { gate.release(); f.clean() }; try await f.seed(openCapture: false)
        let delegate = AppDelegate(historyRecordingModel: f.model)
        // These existing entry points must return before any native setup.
        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("synthetic.launch")))
        f.model.start(); f.model.startRecording(); f.model.registerHotkey()
        delegate.toggleHistory(); f.model.pasteSelected(); let task = f.model.historyPasteTask
        try await until { gate.entered }
        let ticket = f.requests.currentTicket
        delegate.observeHistoryRecording(.stopped)
        #expect(!f.model.busy); #expect(!delegate.recordingHistoryVisible)
        gate.release(); await task?.value
        delegate.toggleHistory(); f.model.pasteCoordinator.rememberDestination(); f.model.pasteSelected()
        #expect(f.requests.currentTicket == ticket); #expect(f.model.historyPasteTask == nil)
        #expect(f.sinks.records.count == 3); #expect(f.model.statusMessage == nil)
    }
    @Test func stopInsideCaptureCannotReopenTicketOrRecordedPresentation() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(openCapture: false)
        let delegate = AppDelegate(historyRecordingModel: f.model)
        let old = f.requests.currentTicket
        f.onCapture = { f.onCapture = nil; f.model.stop() }
        delegate.toggleHistory()
        #expect(f.requests.currentTicket == old); #expect(!delegate.recordingHistoryVisible)
        f.model.pasteSelected()
        #expect(f.sinks.records.isEmpty); #expect(!f.model.busy)
    }

}
