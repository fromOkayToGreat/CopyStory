import Foundation
import Dispatch
import Testing
import CopyStoryCore
@testable import CopyStory

// Actual AppModel entry points; no monitor/start(), GUI, global preferences,
// clipboard, hotkey, login or permission operations. Synthetic stores only.
@Suite(.serialized) @MainActor
struct HistoryRequestPathTests {
    typealias Request = HistoryRequestSimulation
    private let target = Request.Identity(pid: 42, bundleID: "synthetic.target", bundlePath: "/synthetic/target", launchTime: 1)
    @MainActor final class Gate {
        var entered = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            entered = true
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { continuation?.resume(); continuation = nil }
    }
    @MainActor final class Fixture {
        let root: URL
        let suite = "CopyStory.HistoryRequestPath.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: HistoryStore
        let sinks = HistoryRecordingSinks()
        let identity = Request.Identity(pid: 42, bundleID: "synthetic.target", bundlePath: "/synthetic/target", launchTime: 1)
        var snapshot: Request.Snapshot
        var onSnapshot: (() -> Void)?
        var onCapture: (() -> Void)?
        var successfulWrites: [CapturePayload] = []
        var onWrite: (() -> Void)?
        var model: AppModel!
        lazy var requests = Request(ownPID: 1, sinks: sinks, snapshot: { [unowned self] in
            let value = Request.Snapshot(now: self.snapshot.now, frontmost: self.snapshot.frontmost,
                destinationAlive: self.snapshot.destinationAlive, permission: self.snapshot.permission,
                modifiersReleased: self.snapshot.modifiersReleased, boardVersion: self.sinks.boardVersion)
            self.onSnapshot?(); return value
        })
        init(loader: (@MainActor (String) async throws -> CapturePayload)? = nil,
             beforeFinish: @escaping @MainActor () async -> Void = {}) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-HistoryRequest-\(UUID().uuidString)")
            defaults = UserDefaults(suiteName: suite)!
            store = try HistoryStore(directory: root)
            snapshot = Request.Snapshot(now: 1, frontmost: identity)
            model = AppModel(store: store, demo: true, preferenceStore: defaults,
                historyRecording: HistoryRequestRecordingDependencies(requests: requests, captureObservation: { [unowned self] in let value = self.snapshot; self.onCapture?(); return value }, loadPayload: loader,
                    beforeFinish: beforeFinish, onSuccessfulWrite: { [weak self] payload in
                        self?.successfulWrites.append(payload); self?.onWrite?()
                    }))
            model.closePanel = { Issue.record("Recording path must not close a real panel") }
        }
        func seed(openCapture: Bool = true) async throws {
            _ = try await store.capture(CapturePayload(text: "Synthetic first café 🧪\nline\tend  ", capturedAt: Date(timeIntervalSince1970: 2)), limits: HistoryLimits())
            _ = try await store.capture(CapturePayload(text: "Synthetic second", capturedAt: Date(timeIntervalSince1970: 1)), limits: HistoryLimits())
            await model.refresh()
            if openCapture { requests.open(identity: identity, now: 0) }
        }
        func clean() {
            model.cancelPendingSelection()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
    func until(_ predicate: () -> Bool) async throws {
        for _ in 0..<1000 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        try #require(predicate(), "Request path did not settle")
    }
    func finished(_ model: AppModel) async { await model.historyPasteTask?.value }
    func assertNoAdmission(_ f: Fixture) {
        #expect(!f.sinks.records.contains { if case .admissionOpportunity = $0 { true } else { false } })
    }
    @Test func pasteSelectedLoadsRealSyntheticStoreAndReplaysWithoutAdmission() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        let before = try await f.store.search(query: "", filter: .all); let stats = try await f.store.stats()
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.successfulWrites.count == 1)
        #expect(f.successfulWrites.first?.text == "Synthetic first café 🧪\nline\tend  ")
        #expect(f.sinks.records.count == 5) // write attempt/success, dismissal, down/up intentions
        #expect(f.sinks.records.first == .writeAttempt(1, .text("Synthetic first café 🧪\nline\tend  ")))
        assertNoAdmission(f)
        #expect(try await f.store.search(query: "", filter: .all) == before)
        #expect(try await f.store.stats().count == stats.count)
        #expect(!f.model.busy)
        #expect(f.model.statusMessage?.contains("Simulated event intent") == true)
    }
    @Test func directPastePreservesCombinedPayloadAndCallsSuccessfulWriteOnce() async throws {
        let payload = CapturePayload(text: "Synthetic image label", imageData: Data([0, 255, 128]))
        let f = try Fixture(loader: { _ in payload }); defer { f.clean() }; try await f.seed()
        let item = try #require(f.model.items.last)
        f.model.paste(item); await finished(f.model)
        #expect(f.sinks.records.first == .writeAttempt(1, .textAndImage("Synthetic image label", [0, 255, 128])))
        #expect(f.successfulWrites.count == 1); #expect(f.successfulWrites[0].imageData == payload.imageData)
        assertNoAdmission(f)
    }
    @Test func cancelWhilePayloadLoadsPreventsWritesAndFeedback() async throws {
        let gate = Gate()
        let f = try Fixture(loader: { _ in await gate.wait(); return CapturePayload(text: "Synthetic delayed") })
        defer { gate.release(); f.clean() }; try await f.seed()
        f.model.pasteSelected(); let task = f.model.historyPasteTask
        try await until { gate.entered }
        f.model.cancelPendingSelection(); #expect(!f.model.busy)
        gate.release(); await task?.value
        #expect(f.sinks.records.isEmpty); #expect(f.successfulWrites.isEmpty); #expect(f.model.statusMessage == nil)
    }
    @Test func changingSelectionDuringLookupInvalidatesRequestBeforeWrite() async throws {
        let gate = Gate(); let f = try Fixture(loader: { _ in await gate.wait(); return CapturePayload(text: "Synthetic old row") })
        defer { gate.release(); f.clean() }; try await f.seed()
        f.model.pasteSelected(); let task = f.model.historyPasteTask; try await until { gate.entered }
        f.model.select(try #require(f.model.items.last)); gate.release(); await task?.value
        #expect(f.sinks.records.isEmpty); #expect(f.model.statusMessage == nil); #expect(!f.model.busy)
    }
    @Test func queryChangeDuringLookupPreventsWrite() async throws {
        let gate = Gate(); let f = try Fixture(loader: { _ in await gate.wait(); return CapturePayload(text: "Synthetic old query") })
        defer { gate.release(); f.clean() }; try await f.seed()
        f.model.pasteSelected(); let task = f.model.historyPasteTask; try await until { gate.entered }
        f.model.query = "second"; gate.release(); await task?.value
        #expect(f.sinks.records.isEmpty); #expect(f.model.statusMessage == nil)
        try await until { !f.model.isSearching }
    }
    @Test func repeatedRequestsWhileLookupPendingCannotDuplicateWrite() async throws {
        let gate = Gate(); var loads = 0
        let f = try Fixture(loader: { _ in loads += 1; await gate.wait(); return CapturePayload(text: "Synthetic once") })
        defer { gate.release(); f.clean() }; try await f.seed()
        f.model.pasteSelected(); try await until { gate.entered }
        f.model.pasteSelected(); f.model.paste(try #require(f.model.items.first))
        #expect(loads == 1); gate.release(); await finished(f.model)
        #expect(f.successfulWrites.count == 1); #expect(f.sinks.records.count == 5)
    }
    @Test func failedWriteHasNoSuccessCallbackAdmissionOrPairAndCannotRetry() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(); f.sinks.writesSucceed = false
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.sinks.records.count == 2); #expect(f.successfulWrites.isEmpty); assertNoAdmission(f)
        #expect(f.model.statusMessage?.contains("writeFailed") == true)
        f.sinks.writesSucceed = true; f.model.pasteSelected(); await finished(f.model)
        #expect(f.sinks.records.count == 2); #expect(f.successfulWrites.isEmpty)
        #expect(f.model.statusMessage?.contains("consumed") == true)
    }
    @Test func payloadFailureHasNoWriteAndReportsOnlyCurrentFailure() async throws {
        let f = try Fixture(loader: { _ in throw HistoryStoreError.missingItem }); defer { f.clean() }; try await f.seed()
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.sinks.records.isEmpty); #expect(f.successfulWrites.isEmpty)
        #expect(f.model.statusMessage?.contains("stored payload is unavailable") == true)
    }
    @Test func delayedOldSuccessCannotReleaseBusyOrOverwriteNewFeedback() async throws {
        let oldLoad = Gate(); let newFinish = Gate(); var loads = 0
        let f = try Fixture(loader: { _ in
            loads += 1
            if loads == 1 { await oldLoad.wait() }
            return CapturePayload(text: "Synthetic generation \(loads)")
        }, beforeFinish: { await newFinish.wait() })
        defer { oldLoad.release(); newFinish.release(); f.clean() }; try await f.seed()
        f.model.pasteSelected(); let oldTask = f.model.historyPasteTask; try await until { oldLoad.entered }
        f.model.cancelPendingSelection(); f.requests.open(identity: f.identity, now: 0)
        f.model.pasteSelected(); let newTask = f.model.historyPasteTask; try await until { newFinish.entered }
        f.model.showFeedback("New request owns feedback")
        oldLoad.release(); await oldTask?.value
        #expect(f.model.busy); #expect(f.model.statusMessage == "New request owns feedback")
        #expect(f.successfulWrites.count == 1); assertNoAdmission(f)
        newFinish.release(); await newTask?.value
        #expect(!f.model.busy); #expect(f.sinks.records.count == 5)
    }
    @Test func delayedOldErrorCannotOverwriteNewRequestOrRefreshItsSelection() async throws {
        let oldLoad = Gate(); let newFinish = Gate(); var loads = 0
        let f = try Fixture(loader: { _ in
            loads += 1
            if loads == 1 { await oldLoad.wait(); throw HistoryStoreError.missingItem }
            return CapturePayload(text: "Synthetic new request")
        }, beforeFinish: { await newFinish.wait() })
        defer { oldLoad.release(); newFinish.release(); f.clean() }; try await f.seed()
        f.model.pasteSelected(); let oldTask = f.model.historyPasteTask; try await until { oldLoad.entered }
        f.model.cancelPendingSelection(); f.requests.open(identity: f.identity, now: 0)
        f.model.pasteSelected(); let newTask = f.model.historyPasteTask; try await until { newFinish.entered }
        let selected = f.model.selectedID; f.model.showFeedback("New feedback")
        oldLoad.release(); await oldTask?.value
        #expect(f.model.busy); #expect(f.model.statusMessage == "New feedback"); #expect(f.model.selectedID == selected)
        newFinish.release(); await newTask?.value
    }
    @Test func cancelledFinalWaitHasOneSuccessfulWriteCallbackButNoPair() async throws {
        let wait = Gate(); let f = try Fixture(beforeFinish: { await wait.wait() })
        defer { wait.release(); f.clean() }; try await f.seed()
        let before = try await f.store.search(query: "", filter: .all)
        f.model.pasteSelected(); let task = f.model.historyPasteTask; try await until { wait.entered }
        #expect(f.successfulWrites.count == 1); #expect(f.sinks.records.count == 3)
        f.model.cancelPendingSelection(); wait.release(); await task?.value
        #expect(f.sinks.records.count == 3); #expect(f.model.statusMessage == nil); assertNoAdmission(f)
        #expect(try await f.store.search(query: "", filter: .all) == before)
    }
    @Test func writeCallbackCancellationCannotContinueOrPublishFeedback() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.onWrite = { f.model.cancelPendingSelection() }
        f.model.pasteSelected(); let task = f.model.historyPasteTask; await task?.value
        #expect(f.successfulWrites.count == 1); #expect(f.sinks.records.count == 3)
        #expect(f.model.statusMessage == nil); #expect(!f.model.busy)
    }
    @Test func cancellationInsidePrewriteSnapshotStopsActualPathBeforeWrite() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.onSnapshot = { f.onSnapshot = nil; f.model.cancelPendingSelection() }
        f.model.pasteSelected(); let task = f.model.historyPasteTask; await task?.value
        #expect(f.sinks.records.isEmpty); #expect(f.successfulWrites.isEmpty); #expect(f.model.statusMessage == nil)
    }
    @Test func captureSupersededDuringPayloadLoadCannotUseNewTargetCapture() async throws {
        let gate = Gate(); let f = try Fixture(loader: { _ in await gate.wait(); return CapturePayload(text: "Synthetic stale capture") })
        defer { gate.release(); f.clean() }; try await f.seed()
        f.model.pasteSelected(); let task = f.model.historyPasteTask; try await until { gate.entered }
        let newTicket = f.requests.open(identity: f.identity, now: 0)
        gate.release(); await task?.value
        #expect(f.requests.currentTicket == newTicket); #expect(f.requests.feedback == .idle)
        #expect(f.sinks.records.isEmpty); #expect(f.model.statusMessage == nil)
    }
    @Test func permissionDeniedAndUnknownAreTruthfulAndDoNotWrite() async throws {
        for permission: Request.Permission in [.denied, .unknown] {
            let f = try Fixture(); defer { f.clean() }; try await f.seed(); f.snapshot.permission = permission
            f.model.pasteSelected(); await finished(f.model)
            #expect(f.sinks.records.isEmpty); #expect(f.successfulWrites.isEmpty)
            #expect(f.model.statusMessage?.contains(permission == .denied ? "permissionDenied" : "permissionUnknown") == true)
            #expect(f.model.statusMessage?.contains("No real clipboard or events used") == true)
        }
    }
    @Test func oldPayloadErrorAfterSupersededCaptureDoesNotPublishFeedback() async throws {
        let gate = Gate(); let f = try Fixture(loader: { _ in await gate.wait(); throw HistoryStoreError.missingItem })
        defer { gate.release(); f.clean() }; try await f.seed()
        f.model.pasteSelected(); let task = f.model.historyPasteTask; try await until { gate.entered }
        let current = f.requests.open(identity: f.identity, now: 0)
        gate.release(); await task?.value
        #expect(f.model.statusMessage == nil); #expect(f.requests.currentTicket == current)
        #expect(f.requests.feedback == .idle); #expect(f.sinks.records.isEmpty)
    }
    @Test func payloadFailureNeedsFreshCaptureBeforeAnotherWrite() async throws {
        var loads = 0
        let f = try Fixture(loader: { _ in
            loads += 1
            if loads == 1 { throw HistoryStoreError.missingItem }
            return CapturePayload(text: "Synthetic recovered payload")
        })
        defer { f.clean() }; try await f.seed()
        f.model.pasteSelected(); await finished(f.model)
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.sinks.records.isEmpty); #expect(f.successfulWrites.isEmpty)
        f.requests.open(identity: f.identity, now: 0)
        f.model.pasteSelected(); await finished(f.model)
        #expect(f.successfulWrites.count == 1); #expect(f.sinks.records.count == 5)
    }
    @Test func permissionLossSnapshotAtFinalWaitRejectsPairWithoutDuplicateAdmission() async throws {
        let wait = Gate(); let f = try Fixture(beforeFinish: { await wait.wait() })
        defer { wait.release(); f.clean() }; try await f.seed()
        f.model.pasteSelected(); let task = f.model.historyPasteTask; try await until { wait.entered }
        f.snapshot.permission = .denied; wait.release(); await task?.value
        #expect(f.sinks.records.count == 3); #expect(f.successfulWrites.count == 1); assertNoAdmission(f)
        #expect(f.model.statusMessage?.contains("permissionDenied") == true)
    }

    @Test func oldErrorRefreshCannotApplyResultsAfterNewOwnerBegins() async throws {
        let newFinish = Gate(); var loads = 0
        let f = try Fixture(loader: { _ in
            loads += 1
            if loads == 1 { throw HistoryStoreError.missingItem }
            return CapturePayload(text: "Synthetic new owner")
        }, beforeFinish: { await newFinish.wait() })
        defer { newFinish.release(); f.clean() }; try await f.seed()
        let oldItem = try #require(f.model.items.first)
        let newItem = try #require(f.model.items.last)
        try await f.store.delete(id: oldItem.id)
        let release = DispatchSemaphore(value: 0); let store = f.store
        var blocker: Task<Void, Never>?
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            blocker = Task.detached { await store.blockHistoryRefresh(started: { started.resume() }, release: release) }
        }
        defer { release.signal() }
        f.model.pasteSelected(); let oldTask = f.model.historyPasteTask
        try await until { f.model.statusMessage?.contains("stored payload is unavailable") == true }
        // The active error handler is now suspended in refresh behind the store.
        f.model.cancelPendingSelection(); f.model.select(newItem)
        f.requests.open(identity: f.identity, now: 0)
        f.model.pasteSelected(); let newTask = f.model.historyPasteTask
        try await until { newFinish.entered }
        let rows = f.model.items; f.model.showFeedback("Fresh request feedback")
        release.signal(); await blocker?.value; await oldTask?.value
        #expect(f.model.items == rows); #expect(f.model.selectedID == newItem.id)
        #expect(f.model.busy); #expect(f.model.statusMessage == "Fresh request feedback")
        newFinish.release(); await newTask?.value
    }

}


private extension HistoryStore {
    func blockHistoryRefresh(started: @Sendable () -> Void, release: DispatchSemaphore) {
        started(); _ = release.wait(timeout: .now() + 5)
    }
}
