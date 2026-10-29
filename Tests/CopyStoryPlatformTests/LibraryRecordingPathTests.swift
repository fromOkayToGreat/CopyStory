import Foundation
import Dispatch
import Testing
import CopyStoryCore
@testable import CopyStory

// Real Library/AppModel/HistoryStore entry points, concrete recording sinks,
// synthetic files and isolated defaults only. Never starts a monitor or GUI.
@Suite(.serialized) @MainActor
struct LibraryRecordingPathTests {
    typealias Request = HistoryRequestSimulation
    typealias Gate = HistoryRequestPathTests.Gate
    @MainActor final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-LibraryRecording-\(UUID().uuidString)")
        let suite = "CopyStory.LibraryRecording.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: HistoryStore
        let sinks = HistoryRecordingSinks()
        let identity = Request.Identity(pid: 42, bundleID: "synthetic.target", bundlePath: "/synthetic/target", launchTime: 1)
        var permission = Request.Permission.available
        var captureState = HistoryRequestRecordingDependencies.CaptureState(isRecording: true)
        var onWrite: (() -> Void)?
        var writes: [CapturePayload] = []
        var model: AppModel!
        var delegate: AppDelegate!
        lazy var requests = Request(ownPID: 1, sinks: sinks, snapshot: { [unowned self] in
            Request.Snapshot(now: 1, frontmost: self.identity, permission: self.permission, boardVersion: self.sinks.boardVersion)
        })
        init(demo: Bool = false, beforeFinish: @escaping @MainActor () async -> Void = {}) throws {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: "onboardingComplete")
            store = try HistoryStore(directory: root)
            model = AppModel(store: store, demo: demo, preferenceStore: defaults,
                historyRecording: .init(requests: requests,
                    captureObservation: { [unowned self] in .init(now: 0, frontmost: self.identity) },
                    captureState: { [unowned self] in self.captureState },
                    beforeFinish: beforeFinish,
                    onSuccessfulWrite: { [weak self] payload in self?.writes.append(payload); self?.onWrite?() }))
            model.closePanel = { Issue.record("Offline path reached real closePanel") }
            delegate = AppDelegate(historyRecordingModel: model)
            open()
        }
        lazy var entry: LibraryEntry = {
            LibraryEntry(title: "Synthetic prompt", template: "  {{topic}}\n{{tone}} 🧪\tend  ", variables: [
                .init(name: "topic", defaultValue: "Café 日本語"),
                .init(name: "tone", kind: .dropdown, defaultValue: "Friendly", options: ["Friendly", "Concise"])])
        }()
        func open() { delegate.toggleHistory(); model.library.open(entry) }
        func clean() {
            model.stop(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        func finish() async { await model.historyPasteTask?.value }
        func texts() async throws -> [String] {
            var output: [String] = []
            for row in try await store.search(query: "", filter: .all) {
                output.append(try await store.fullText(id: row.id) ?? "")
            }
            return output
        }
        var pairs: Int { sinks.records.filter { if case .eventIntent = $0 { true } else { false } }.count }
        var expected: String { "  Café 日本語\nFriendly 🧪\tend  " }
    }
    func until(_ condition: () -> Bool) async throws { try await HistoryRequestPathTests().until(condition) }

    @Test func pasteFreezesExactRenderedPayloadBeforeOwnedHideAndAdmitsOnce() async throws {
        let f = try Fixture(); defer { f.clean() }
        try await f.model.library.store?.create(f.entry)
        f.model.library.values["topic"] = "First\nsecond"
        let expected = "  First\nsecond\nFriendly 🧪\tend  "
        f.model.usePrompt(copyOnly: false); await f.finish()
        #expect(f.writes.map(\.text) == [expected]); #expect(try await f.texts() == [expected])
        #expect(f.model.library.screen == .browse && f.model.library.values.isEmpty)
        #expect(!f.delegate.recordingHistoryVisible); #expect(f.pairs == 2)
        #expect(f.sinks.records.first == .writeAttempt(1, .text(expected)))
        #expect(f.sinks.records.contains(.admissionOpportunity(1)))
        #expect(f.model.statusMessage?.contains("no real paste") == true)
        #expect(try await f.model.library.store?.entry(id: f.entry.id)?.defaultValues == f.entry.defaultValues)
    }
    @Test func commandReturnUsesSameFormActionAndEditorReturnRemainsUnhandled() async throws {
        let f = try Fixture(); defer { f.clean() }
        #expect(f.model.handleLibraryCommandReturn()); await f.finish()
        #expect(try await f.texts() == [f.expected]); #expect(f.pairs == 2)
        #expect(!f.model.handleLibraryCommandReturn())
        f.model.library.edit(f.entry)
        #expect(!f.model.handleLibraryCommandReturn()); #expect(f.writes.count == 1)
    }
    @Test func explicitCopyKeepsFormValuesAndNeverSchedulesDismissalOrPair() async throws {
        let f = try Fixture(); defer { f.clean() }
        f.permission = .denied
        f.model.usePrompt(copyOnly: true); await f.finish()
        f.model.usePrompt(copyOnly: true); await f.finish()
        #expect(f.writes.count == 2); #expect(try await f.texts() == [f.expected])
        #expect(f.delegate.recordingHistoryVisible && f.model.library.screen == .use)
        #expect(f.model.library.values == f.entry.defaultValues); #expect(f.pairs == 0)
        #expect(!f.sinks.records.contains { if case .dismissalIntent = $0 { true } else { false } })
        #expect(f.model.statusMessage?.contains("Simulated Copy") == true)
    }
    @Test(arguments: [true, false]) func failedWritesKeepFormAndAdmitNothing(copy: Bool) async throws {
        let f = try Fixture(); defer { f.clean() }; f.sinks.writesSucceed = false
        f.model.usePrompt(copyOnly: copy); await f.finish()
        #expect(f.writes.isEmpty && f.pairs == 0); #expect(try await f.texts().isEmpty)
        #expect(f.model.library.screen == .use && f.delegate.recordingHistoryVisible)
        #expect(f.model.statusMessage?.contains("writeFailed") == true)
    }
    @Test(arguments: ["close", "edit", "back", "reopen", "section", "stop", "cancel"])
    func cancellationBeforeTaskWritesNothing(action: String) async throws {
        let f = try Fixture(); defer { f.clean() }
        f.model.usePrompt(copyOnly: false); let task = f.model.historyPasteTask
        switch action {
        case "close": f.delegate.closeHistory()
        case "edit": f.model.library.values["topic"] = "new value"
        case "back": f.model.library.back()
        case "reopen": f.model.library.open(f.entry)
        case "section": f.model.library.section = .history
        case "stop": f.model.stop()
        default: f.model.cancelPendingSelection()
        }
        await task?.value
        #expect(f.sinks.records.isEmpty && f.writes.isEmpty); #expect(try await f.texts().isEmpty)
        #expect(!f.model.busy); #expect(f.model.statusMessage == nil)
    }
    @Test(arguments: ["paused", "locked", "monitorLocked", "notRecording", "onboarding", "demo", "excluded"])
    func successfulWriteAdmissionRespectsExistingEligibility(policy: String) async throws {
        let f = try Fixture(demo: policy == "demo"); defer { f.clean() }
        switch policy {
        case "paused": f.model.paused = true
        case "locked": f.model.isLocked = true
        case "monitorLocked": f.captureState.isLocked = true
        case "notRecording": f.captureState.isRecording = false
        case "onboarding": f.model.onboardingComplete = false
        case "excluded": f.model.setExcludedApps([Bundle.main.bundleIdentifier ?? "app.copystory"])
        default: break
        }
        f.model.usePrompt(copyOnly: true); await f.finish()
        #expect(f.writes.count == 1); #expect(try await f.texts().isEmpty)
        #expect(f.pairs == 0)
    }
    @Test func deniedPasteWritesNothingAndExplicitCopyRemainsAvailable() async throws {
        let f = try Fixture(); defer { f.clean() }; f.permission = .denied
        f.model.usePrompt(copyOnly: false); await f.finish()
        #expect(f.sinks.records.isEmpty); #expect(try await f.texts().isEmpty)
        #expect(f.model.library.screen == .use)
        f.model.usePrompt(copyOnly: true); await f.finish()
        #expect(f.writes.count == 1); #expect(try await f.texts() == [f.expected]); #expect(f.pairs == 0)
    }
    @Test func ownedHideDoesNotCancelPendingRequestButUserDismissalDoes() async throws {
        let gate = Gate(); let f = try Fixture(beforeFinish: { await gate.wait() })
        defer { gate.release(); f.clean() }
        f.model.usePrompt(copyOnly: false); let task = f.model.historyPasteTask
        try await until { gate.entered }
        #expect(!f.delegate.recordingHistoryVisible && f.model.library.screen == .browse)
        #expect(f.requests.feedback == .waiting && f.model.busy)
        f.delegate.closeHistory(); gate.release(); await task?.value
        #expect(f.pairs == 0); #expect(try await f.texts() == [f.expected])
        #expect(f.model.statusMessage == nil)
    }
    @Test func staleFinishCannotClearNewFormBusyOrFeedback() async throws {
        let gate = Gate(); let f = try Fixture(beforeFinish: { await gate.wait() })
        defer { gate.release(); f.clean() }
        f.model.usePrompt(copyOnly: false); let old = f.model.historyPasteTask
        try await until { gate.entered }
        f.open(); f.model.library.values["topic"] = "new form"
        f.model.usePrompt(copyOnly: true); let newer = f.model.historyPasteTask
        gate.release(); await old?.value
        await newer?.value
        #expect(f.model.library.screen == .use && f.model.library.values["topic"] == "new form")
        #expect(f.delegate.recordingHistoryVisible && !f.model.busy)
        #expect(f.model.statusMessage?.contains("Simulated Copy") == true)
        #expect(f.pairs == 0); #expect(try await f.texts().count == 2)
    }
    @Test func stalePasteCompletionCannotReleaseNewerPendingOwner() async throws {
        let first = Gate(), second = Gate()
        var finishes = 0
        let f = try Fixture(beforeFinish: {
            finishes += 1
            if finishes == 1 { await first.wait() } else { await second.wait() }
        })
        defer { first.release(); second.release(); f.clean() }
        f.model.usePrompt(copyOnly: false); let old = f.model.historyPasteTask
        try await until { first.entered }
        f.open(); f.model.library.values["topic"] = "new pending"
        f.model.usePrompt(copyOnly: false); let newer = f.model.historyPasteTask
        try await until { second.entered }
        first.release(); await old?.value
        #expect(f.model.busy && f.requests.feedback == .waiting)
        #expect(f.model.statusMessage == nil && f.pairs == 0)
        second.release(); await newer?.value
        #expect(!f.model.busy && f.pairs == 2)
        #expect(try await f.texts().count == 2)
    }
    @Test func repeatedFormActionsWhileBusyCannotDuplicateWriteOrAdmission() async throws {
        let gate = Gate(); let f = try Fixture(beforeFinish: { await gate.wait() })
        defer { gate.release(); f.clean() }
        f.model.usePrompt(copyOnly: false); let task = f.model.historyPasteTask
        f.model.usePrompt(copyOnly: false); f.model.usePrompt(copyOnly: true)
        try await until { gate.entered }
        f.model.usePrompt(copyOnly: false)
        gate.release(); await task?.value
        #expect(f.writes.count == 1 && f.pairs == 2)
        #expect(try await f.texts() == [f.expected])
    }
    @Test func permissionLossAfterSuccessfulWriteKeepsAdmissionButRecordsNoPair() async throws {
        let gate = Gate(); let f = try Fixture(beforeFinish: { await gate.wait() })
        defer { gate.release(); f.clean() }
        f.model.usePrompt(copyOnly: false); let task = f.model.historyPasteTask
        try await until { gate.entered }; f.permission = .denied
        gate.release(); await task?.value
        #expect(f.pairs == 0); #expect(try await f.texts() == [f.expected])
        #expect(f.model.statusMessage?.contains("permissionDenied") == true)
    }
    @Test func admittedSavePrecedesReentrantClearAndLaterSaveFollowsClear() async throws {
        let f = try Fixture(); defer { f.clean() }
        var clear: Task<Void, Never>?
        f.onWrite = { clear = f.model.clear(includePinned: true) }
        f.model.usePrompt(copyOnly: true); await f.finish(); await clear?.value
        #expect(try await f.texts().isEmpty)
        f.onWrite = nil; f.model.library.values["topic"] = "after clear"
        f.model.usePrompt(copyOnly: true); await f.finish()
        #expect(try await f.texts() == ["  after clear\nFriendly 🧪\tend  "])
    }
    @Test func failedAdmissionRetainsSuccessfulCopyAndDoesNotOverwriteNewerFeedback() async throws {
        let f = try Fixture(); defer { f.clean() }
        await f.model.save(CapturePayload(text: "pinned synthetic")).value
        let pinned = try #require(f.model.items.first)
        try await f.store.setPinned(id: pinned.id, pinned: true); f.model.maxItems = 1
        let release = DispatchSemaphore(value: 0); defer { release.signal() }
        await withCheckedContinuation { (entered: CheckedContinuation<Void, Never>) in
            Task.detached { await f.store.holdForRecordingTest(started: { entered.resume() }, release: release) }
        }
        f.model.usePrompt(copyOnly: true); let old = f.model.historyPasteTask
        try await until { f.writes.count == 1 }
        f.model.library.open(f.entry); f.model.showFeedback("New form feedback")
        release.signal(); await old?.value
        #expect(f.model.statusMessage == "New form feedback")
        #expect(f.model.library.screen == .use && f.model.library.values == f.entry.defaultValues)
        #expect(try await f.texts() == ["pinned synthetic"]); #expect(f.pairs == 0)
    }
    @Test func unchangedFormCapacityFailureReportsHistoryLimitTruthfully() async throws {
        let f = try Fixture(); defer { f.clean() }
        await f.model.save(CapturePayload(text: "pinned synthetic")).value
        let pinned = try #require(f.model.items.first)
        try await f.store.setPinned(id: pinned.id, pinned: true); f.model.maxItems = 1
        f.model.usePrompt(copyOnly: true); await f.finish()
        #expect(f.writes.count == 1); #expect(try await f.texts() == ["pinned synthetic"])
        #expect(f.model.statusMessage?.contains("history is full") == true)
    }
    @Test func pasteFinalWaitPreservesCurrentHistoryCapacityFeedback() async throws {
        let gate = Gate(); let f = try Fixture(beforeFinish: { await gate.wait() })
        defer { gate.release(); f.clean() }
        await f.model.save(CapturePayload(text: "pinned synthetic")).value
        let pinned = try #require(f.model.items.first)
        try await f.store.setPinned(id: pinned.id, pinned: true); f.model.maxItems = 1
        f.model.usePrompt(copyOnly: false); let task = f.model.historyPasteTask
        try await until { gate.entered && f.model.statusMessage?.contains("history is full") == true }
        let admissionFeedback = f.model.statusMessage
        gate.release(); await task?.value
        #expect(f.model.statusMessage == admissionFeedback)
        #expect(f.model.statusMessage?.contains("Simulated write recorded") == true)
        #expect(f.pairs == 2); #expect(try await f.texts() == ["pinned synthetic"])
    }
    @Test func supersededDiscardConfirmationCannotResetNewerForm() throws {
        let f = try Fixture(); defer { f.clean() }
        f.model.library.edit(f.entry); f.model.library.draft?.title = "Changed"
        f.delegate.closeHistory(); #expect(f.model.library.confirmDiscard)
        f.model.library.open(f.entry)
        f.model.library.values["topic"] = "newer form"
        f.model.library.discardChanges()
        #expect(f.delegate.recordingHistoryVisible && f.model.library.screen == .use)
        #expect(f.model.library.values["topic"] == "newer form")
        #expect(!f.model.library.confirmDiscard && f.sinks.records.isEmpty)
    }
    @Test func dirtyEditorUserDismissalRetainsExistingDiscardConfirmation() throws {
        let f = try Fixture(); defer { f.clean() }
        f.model.library.edit(f.entry); f.model.library.draft?.title = "Changed"
        f.delegate.closeHistory()
        #expect(f.model.library.confirmDiscard && f.delegate.recordingHistoryVisible)
        f.model.library.cancelDiscard(); #expect(f.model.library.draft?.title == "Changed")
        f.delegate.closeHistory(); f.model.library.discardChanges()
        #expect(!f.delegate.recordingHistoryVisible && f.model.library.screen == .browse)
        #expect(f.sinks.records.isEmpty)
    }
    @Test func excludedAppIDsPersistAndBlockSyntheticQueuedCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "CopyStory.ExclusionTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(directory: root)
        let model = AppModel(store: store, demo: true, preferenceStore: defaults)
        let id = "example.copystory.synthetic-exclusion"
        let pending = model.save(CapturePayload(text: "neutral excluded fixture", sourceBundleID: id))
        model.setExcludedApps([id, id, ""])
        await pending.value
        #expect(model.excludedAppBundleIDs == [id])
        #expect(defaults.stringArray(forKey: "excludedAppBundleIDs") == [id])
        #expect(try await store.stats().count == 0)
        let reloaded = AppModel(store: store, demo: true, preferenceStore: defaults)
        #expect(reloaded.excludedAppBundleIDs == [id])
        await reloaded.save(CapturePayload(text: "neutral allowed fixture", sourceBundleID: "example.allowed")).value
        #expect(try await store.stats().count == 1)
        reloaded.setExcludedApps([])
        await reloaded.save(CapturePayload(text: "neutral unexcluded fixture", sourceBundleID: id)).value
        #expect(try await store.stats().count == 2)
    }
}
private extension HistoryStore {
    func holdForRecordingTest(started: @Sendable () -> Void, release: DispatchSemaphore) {
        started(); #expect(release.wait(timeout: .now() + 10) == .success)
    }

}
