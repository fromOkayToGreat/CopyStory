import Foundation
import Testing
import CopyStoryCore
@testable import CopyStory

// The real DEFAULT dependency-selection branch with an injected environment.
// No History recording dependency, app launch, UI/events, pasteboard, platform
// permission call, monitor, settings or ServiceManagement operation is used.
@Suite(.serialized) @MainActor
struct NativeSourceIntegrationTests {
    typealias Request = HistoryRequestSimulation
    @MainActor final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-NativeSource-\(UUID().uuidString)")
        let suite = "CopyStory.NativeSource.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: HistoryStore
        let target = Request.Identity(pid: 42, bundleID: "synthetic.target", bundlePath: "/synthetic/target", launchTime: 1)
        let own = Request.Identity(pid: 1, bundleID: "synthetic.copystory", bundlePath: "/synthetic/copy", launchTime: 1)
        let third = Request.Identity(pid: 99, bundleID: "synthetic.third", bundlePath: "/synthetic/third", launchTime: 1)
        var front: Request.Identity?
        var secureInput = false
        var alive = true, permission = Request.Permission.available, modifiers = true
        var boardVersion = 0, clock = 1.0, writeSucceeds = true, activationSucceeds = true
        var writes: [HistoryRecordingSinks.Payload] = []
        var activations: [Request.Identity] = []
        var pairs: [(Request.Identity, Int)] = []
        var postFailure: Request.Reason?
        var handlers: [@MainActor (HistoryRecordingObservation) -> Void] = []
        var removals = 0, waits = 0
        var onWait: (() async -> Void)?
        var onActivate: (() -> Void)?
        var onWrite: (() -> Void)?
        var model: AppModel!
        var delegate: AppDelegate!
        lazy var environment = NativePasteEnvironment(ownPID: 1,
            capture: { [unowned self] in .init(now: 0, frontmost: self.front, boardVersion: self.boardVersion) },
            snapshot: { [unowned self] _, presented in
                .init(now: self.clock, frontmost: self.front, destinationAlive: self.alive,
                    permission: self.permission, modifiersReleased: self.modifiers,
                    boardVersion: self.boardVersion, presentationOwnsFocus: presented, secureInput: self.secureInput)
            }, write: { [unowned self] payload in
                self.writes.append(payload); self.boardVersion += 1; self.onWrite?()
                return self.writeSucceeds ? self.boardVersion : nil
            }, activate: { [unowned self] identity in
                self.activations.append(identity)
                guard self.activationSucceeds else { return false }
                self.front = identity; self.onActivate?(); return true
            }, postPair: { [unowned self] identity, version in
                if let failure = self.postFailure { return .blocked(failure) }
                self.pairs.append((identity, version)); return .requested
            }, observe: { [unowned self] handler in
                self.handlers.append(handler)
                return { [weak self] in self?.removals += 1 }
            }, captureState: { .init(isRecording: true) },
            wait: { [unowned self] in self.waits += 1; await self.onWait?() })
        init(optIn: Bool = true, developmentDefaults: Bool = false) throws {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: "onboardingComplete")
            store = try HistoryStore(directory: root)
            front = target
            model = AppModel(store: store, demo: false, preferenceStore: defaults, nativeEnvironment: environment, developmentDefaults: developmentDefaults)
            if optIn { model.setDirectPasteEnabled(true) }
            delegate = AppDelegate(historyRecordingModel: model)
        }
        func open() { delegate.toggleHistory(); front = own }
        func finish() async { await model.historyPasteTask?.value }
        func seed() async throws {
            _ = try await store.capture(CapturePayload(text: "Synthetic history café 🧪\nend  "), limits: .init())
            await model.refresh(); open()
        }
        var entry: LibraryEntry { .init(title: "Synthetic", template: "Hello {{name}} 🧪\n", variables: [.init(name: "name", defaultValue: "Café")]) }
        func clean() {
            model.stop(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
    @Test(arguments: [false, true])
    func developmentDefaultsRequireOptInForHistoryAndLibrary(library: Bool) async throws {
        let f = try Fixture(optIn: false, developmentDefaults: true); defer { f.clean() }
        #expect(!f.model.shortcutEnabled && !f.model.directPasteEnabled)
        #expect(!f.defaults.bool(forKey: "shortcutEnabled") && !f.defaults.bool(forKey: "directPasteEnabled"))
        try await f.seed()
        if library { f.model.library.open(f.entry); f.model.usePrompt(copyOnly: false) }
        else { f.model.pasteSelected() }
        await f.finish()
        #expect(f.writes.isEmpty && f.activations.isEmpty && f.pairs.isEmpty)
        #expect(!f.model.busy && f.model.historyPasteTask == nil)
        #expect(f.model.statusMessage?.contains("Direct Paste is off") == true)
        f.model.setDirectPasteEnabled(true)
        #expect(f.defaults.bool(forKey: "directPasteEnabled"))
        if library { f.model.usePrompt(copyOnly: false) } else { f.model.pasteSelected() }
        await f.finish()
        #expect(f.writes.count == 1 && f.activations.count == 1 && f.pairs.count == 1)
    }
    @Test(arguments: [false, true])
    func copyRemainsAvailableWithDevelopmentDirectPasteOff(library: Bool) async throws {
        let f = try Fixture(optIn: false, developmentDefaults: true); defer { f.clean() }; try await f.seed()
        if library { f.model.library.open(f.entry); f.model.usePrompt(copyOnly: true) }
        else { f.model.copySelected() }
        await f.finish()
        #expect(f.writes.count == 1 && f.activations.isEmpty && f.pairs.isEmpty)
        #expect(!f.model.directPasteEnabled)
    }
    @Test(arguments: [false, true])
    func disablingDirectPasteCancelsPendingWorkAndCannotPost(afterWrite: Bool) async throws {
        let f = try Fixture(developmentDefaults: true); defer { f.clean() }; try await f.seed()
        if afterWrite { f.onWrite = { f.model.setDirectPasteEnabled(false) } }
        else {
            f.modifiers = false
            f.onWait = { f.model.setDirectPasteEnabled(false) }
        }
        f.model.pasteSelected()
        let task = try #require(f.model.historyPasteTask)
        await task.value
        #expect(!f.model.directPasteEnabled && !f.defaults.bool(forKey: "directPasteEnabled"))
        #expect(f.writes.count == (afterWrite ? 1 : 0))
        #expect(f.activations.isEmpty && f.pairs.isEmpty && !f.model.busy)
        f.modifiers = true
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes.count == (afterWrite ? 1 : 0) && f.pairs.isEmpty)
        #expect(f.model.statusMessage?.contains("Direct Paste is off") == true)
    }
    @Test func historyCopyWithoutInvocationOrPermissionDoesNotActivateOrPost() async throws {
        let f = try Fixture(); defer { f.clean() }
        f.front = nil; f.permission = .unknown; f.secureInput = true
        _ = try await f.store.capture(CapturePayload(text: "Copy without recipient"), limits: .init())
        await f.model.refresh()
        f.model.copySelected(); await f.finish()
        #expect(f.writes == [.text("Copy without recipient")])
        #expect(f.activations.isEmpty && f.pairs.isEmpty)
        #expect(f.model.statusMessage == "Copied. Press ⌘V in your intended app.")
    }
    @Test func libraryCopyWithoutInvocationOrPermissionDoesNotActivateOrPost() async throws {
        let f = try Fixture(); defer { f.clean() }
        f.front = nil; f.permission = .denied; f.secureInput = true
        f.model.library.open(f.entry)
        f.model.usePrompt(copyOnly: true); await f.finish()
        #expect(f.writes.count == 1)
        #expect(f.activations.isEmpty && f.pairs.isEmpty)
        #expect(f.model.statusMessage?.hasPrefix("Copied.") == true)
    }
    @Test(arguments: [false, true])
    func secureInputCancelsBeforeWriteOrAfterWriteWithoutRetry(afterWrite: Bool) async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        if afterWrite { f.onWrite = { f.secureInput = true } } else { f.secureInput = true }
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes.count == (afterWrite ? 1 : 0))
        #expect(f.activations.isEmpty && f.pairs.isEmpty)
        #expect(f.model.statusMessage?.contains("secure input") == true)
        f.secureInput = false
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes.count == (afterWrite ? 1 : 0))
        #expect(f.pairs.isEmpty)
    }
    @Test func defaultHistoryUsesNativeAdapterOwnedPresentationAndFixedIdentity() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes == [.text("Synthetic history café 🧪\nend  ")])
        #expect(f.activations == [f.target]); #expect(f.pairs.count == 1)
        #expect(f.pairs.first?.0 == f.target && f.pairs.first?.1 == 1)
        #expect(!f.delegate.recordingHistoryVisible && !f.model.busy)
        #expect(try await f.store.stats().count == 1)
        #expect(f.model.statusMessage?.contains("no insertion is confirmed") == true)
        #expect(f.model.statusMessage?.contains("No automatic retry") == true)
    }
    @Test func contextMenuOwnsActivationAndDefersPanelUntilTrackingReturns() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.delegate.closeHistory(); f.front = f.target
        var trackingReturned = false
        var menuGeneration: UUID?
        let ticket = try #require(f.delegate.trackContextMenuInvocation { ticket in
            menuGeneration = f.delegate.currentContextMenuGeneration
            let handler = f.handlers.last!
            f.front = f.own; handler(.activated(f.own))
            #expect(!f.model.pasteCoordinator.nativeAdapter.requests.isCancelled)
            f.delegate.openContextMenuInvocation(ticket: ticket, generation: menuGeneration!)
            #expect(!f.delegate.recordingHistoryVisible, "Open choice must not present a panel during menu tracking")
            #expect(f.model.recordingInvocationTicket == ticket && f.writes.isEmpty)
            trackingReturned = true
        })
        #expect(trackingReturned && f.delegate.recordingHistoryVisible)
        #expect(f.model.recordingInvocationTicket == ticket)
        f.model.pasteSelected(); await f.finish()
        #expect(f.pairs.count == 1 && f.pairs.first?.0 == f.target)
        f.delegate.openContextMenuInvocation(ticket: ticket, generation: menuGeneration!)
        f.delegate.finishContextMenuInvocation(ticket: ticket, generation: menuGeneration!)
        #expect(!f.delegate.recordingHistoryVisible && f.pairs.count == 1)
    }
    @Test func menuDismissalWithoutOpenInvalidatesCaptureAfterTracking() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.delegate.closeHistory(); f.front = f.target
        var menuGeneration: UUID?
        let ticket = try #require(f.delegate.trackContextMenuInvocation { _ in
            menuGeneration = f.delegate.currentContextMenuGeneration
            f.front = f.own; f.handlers.last?(.activated(f.own))
            #expect(!f.model.pasteCoordinator.nativeAdapter.requests.isCancelled)
            #expect(!f.delegate.recordingHistoryVisible)
        })
        #expect(f.model.pasteCoordinator.nativeAdapter.requests.isCancelled)
        f.delegate.openContextMenuInvocation(ticket: ticket, generation: menuGeneration!)
        f.delegate.finishContextMenuInvocation(ticket: ticket, generation: menuGeneration!)
        f.model.pasteSelected(); await f.finish()
        #expect(!f.delegate.recordingHistoryVisible && f.writes.isEmpty && f.pairs.isEmpty)
    }
    @Test(arguments: ["activation", "space", "sleep", "termination", "stop"])
    func menuCancellationCannotPresentEvenAfterOpenChoice(reason: String) async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.delegate.closeHistory(); f.front = f.target
        let ticket = try #require(f.delegate.trackContextMenuInvocation { ticket in
            let handler = f.handlers.last!
            f.front = f.own; handler(.activated(f.own))
            f.delegate.openContextMenuInvocation(ticket: ticket, generation: f.delegate.currentContextMenuGeneration!)
            switch reason {
            case "activation": f.front = f.third; handler(.activated(f.third)); f.front = f.own; handler(.activated(f.own))
            case "space": handler(.spaceChanged)
            case "sleep": handler(.sleep)
            case "termination": handler(.terminated(f.target))
            default: f.model.stop()
            }
            #expect(!f.delegate.recordingHistoryVisible)
        })
        #expect(f.model.recordingInvocationTicket == ticket)
        f.model.pasteSelected(); await f.finish()
        #expect(!f.delegate.recordingHistoryVisible && f.writes.isEmpty && f.pairs.isEmpty)
    }
    @Test(arguments: [true, false])
    func staleMenuActionAndCompletionCannotConsumeNewMenuOwner(openNew: Bool) async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.delegate.closeHistory(); f.front = f.target
        let old = try #require(f.delegate.beginContextMenuInvocation())
        let oldGeneration = try #require(f.delegate.currentContextMenuGeneration)
        let oldObserver = try #require(f.handlers.last)
        f.front = f.target
        let newer = try #require(f.delegate.beginContextMenuInvocation())
        let newerGeneration = try #require(f.delegate.currentContextMenuGeneration)
        f.front = f.own; f.handlers.last?(.activated(f.own))
        if openNew { f.delegate.openContextMenuInvocation(ticket: newer, generation: newerGeneration) }
        f.delegate.openContextMenuInvocation(ticket: old, generation: oldGeneration)
        f.delegate.finishContextMenuInvocation(ticket: old, generation: oldGeneration)
        oldObserver(.sleep)
        #expect(f.model.recordingInvocationTicket == newer && !f.model.pasteCoordinator.nativeAdapter.requests.isCancelled)
        #expect(!f.delegate.recordingHistoryVisible)
        f.delegate.finishContextMenuInvocation(ticket: newer, generation: newerGeneration)
        #expect(f.delegate.recordingHistoryVisible == openNew)
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes.count == (openNew ? 1 : 0) && f.pairs.count == (openNew ? 1 : 0))
    }
    @Test func pasteOwnedHideSurvivesExpectedResignActiveNotification() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.onActivate = { f.delegate.applicationDidResignActive(Notification(name: .init("synthetic-resign"))) }
        f.model.pasteSelected(); await f.finish()
        #expect(f.pairs.count == 1 && !f.model.busy)
    }
    @Test func defaultHistoryCopyIsSeparateAndDoesNotHideActivatePostOrAdmit() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(); f.permission = .unknown
        f.model.copySelected(); await f.finish()
        #expect(f.writes.count == 1 && f.pairs.isEmpty && f.activations.isEmpty)
        #expect(f.delegate.recordingHistoryVisible); #expect(try await f.store.stats().count == 1)
        #expect(f.model.statusMessage?.contains("Copied. Press") == true)
    }
    @Test func defaultLibraryCommandReturnFreezesRenderedTextAndAdmitsBeforeRestoreClear() async throws {
        let f = try Fixture(); defer { f.clean() }; f.open(); f.model.library.open(f.entry)
        f.model.library.values["name"] = "日本語\nCafé"
        var clear: Task<Void, Never>?
        f.onActivate = { clear = f.model.clear(includePinned: true) }
        #expect(f.model.handleLibraryCommandReturn()); await f.finish(); await clear?.value
        #expect(f.writes == [.text("Hello 日本語\nCafé 🧪\n")])
        #expect(f.pairs.count == 1 && f.pairs.first?.0 == f.target)
        #expect(f.model.library.screen == .browse && !f.delegate.recordingHistoryVisible)
        #expect(try await f.store.stats().count == 0, "Admitted save must precede clear invoked during restoration")
    }
    @Test func defaultLibraryExplicitCopyKeepsValuesAndUsesExistingDeduplication() async throws {
        let f = try Fixture(); defer { f.clean() }; f.open(); f.model.library.open(f.entry)
        f.permission = .denied
        f.model.usePrompt(copyOnly: true); await f.finish()
        f.model.usePrompt(copyOnly: true); await f.finish()
        #expect(f.writes.count == 2 && f.pairs.isEmpty && f.activations.isEmpty)
        #expect(f.model.library.screen == .use && f.delegate.recordingHistoryVisible)
        #expect(try await f.store.stats().count == 1)
    }
    @Test(arguments: [true, false]) func failedWriteAdmitsNothingAndKeepsPresentation(library: Bool) async throws {
        let f = try Fixture(); defer { f.clean() }; f.writeSucceeds = false
        if library { f.open(); f.model.library.open(f.entry); f.model.usePrompt(copyOnly: false) }
        else { try await f.seed(); f.model.pasteSelected() }
        await f.finish()
        #expect(f.writes.count == 1 && f.pairs.isEmpty && f.activations.isEmpty)
        #expect(f.delegate.recordingHistoryVisible); #expect(try await f.store.stats().count == (library ? 0 : 1))
        #expect(f.model.statusMessage?.contains("clipboard may have changed") == true)
    }
    @Test func missingOrOwnInvocationNeverReusesPreviousExternalApp() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.delegate.closeHistory(); f.front = f.own; f.delegate.toggleHistory()
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes.isEmpty && f.activations.isEmpty && f.pairs.isEmpty)
        #expect(f.model.statusMessage?.contains("captured app is unavailable") == true)
    }
    @Test func thirdAppActivationIsStickyWhileOwnedActivationIsExpected() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        let handler = try #require(f.handlers.last)
        handler(.activated(f.own)); #expect(f.model.pasteCoordinator.nativeAdapter.requests.feedback == .idle)
        handler(.activated(f.third)); handler(.activated(f.target))
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes.isEmpty && f.pairs.isEmpty)
        #expect(f.model.statusMessage?.contains("cancelled") == true)
    }
    @Test(arguments: ["space", "sleep", "termination", "close"])
    func cancellationBeforeWriteNeverAdmitsOrPosts(reason: String) async throws {
        let f = try Fixture(); defer { f.clean() }; f.open(); f.model.library.open(f.entry)
        f.model.usePrompt(copyOnly: false); let task = f.model.historyPasteTask
        let handler = try #require(f.handlers.last)
        switch reason {
        case "space": handler(.spaceChanged)
        case "sleep": handler(.sleep)
        case "termination": handler(.terminated(f.target))
        default: f.delegate.closeHistory()
        }
        await task?.value
        #expect(f.writes.isEmpty && f.pairs.isEmpty); #expect(try await f.store.stats().count == 0)
    }
    @Test func lateObserverFromOldInvocationCannotCancelNewCapture() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        let old = try #require(f.handlers.last)
        f.delegate.closeHistory(); f.front = f.target; f.open()
        old(.sleep); f.model.pasteSelected(); await f.finish()
        #expect(f.pairs.count == 1 && f.removals >= 1)
    }
    // The static source-gate verifier pins sessionDidResignActiveNotification
    // to .sleep in the native observer. Inject that observation here; no real
    // notification center, session transition, clipboard or event is used.
    @Test(arguments: [false, true], ["beforeTask", "prewriteWait", "write", "activation"])
    func sessionResignationCancelsBothPasteOriginsWithoutRetry(library: Bool, boundary: String) async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        if library { f.model.library.open(f.entry) }
        let resign = try #require(f.handlers.last)
        switch boundary {
        case "prewriteWait":
            f.modifiers = false; f.onWait = { resign(.sleep) }
        case "write": f.onWrite = { resign(.sleep) }
        case "activation": f.onActivate = { resign(.sleep) }
        default: break
        }
        if library { f.model.usePrompt(copyOnly: false) } else { f.model.pasteSelected() }
        let task = try #require(f.model.historyPasteTask)
        if boundary == "beforeTask" { resign(.sleep) }
        await task.value
        let expectedWrites = ["write", "activation"].contains(boundary) ? 1 : 0
        #expect(f.writes.count == expectedWrites)
        #expect(f.activations.count == (boundary == "activation" ? 1 : 0))
        #expect(f.pairs.isEmpty && !f.model.busy && f.model.historyPasteTask == nil)
        #expect(f.model.pasteCoordinator.nativeAdapter.requests.isCancelled)
        #expect(try await f.store.stats().count == (library && boundary == "activation" ? 2 : 1))
        // Return to the original app cannot revive the cancelled invocation.
        f.modifiers = true; f.front = f.target; resign(.activated(f.target))
        if library { f.model.library.open(f.entry); f.model.usePrompt(copyOnly: false) }
        else { f.model.pasteSelected() }
        await f.finish()
        #expect(f.writes.count == expectedWrites && f.pairs.isEmpty)
    }
    @Test(arguments: [false, true], [false, true])
    func sessionResignationDuringWaitCannotClobberFreshInvocation(library: Bool, afterWrite: Bool) async throws {
        let gate = HistoryRequestPathTests.Gate()
        let f = try Fixture(); defer { gate.release(); f.clean() }; try await f.seed()
        if library { f.model.library.open(f.entry) }
        if afterWrite { f.onActivate = { f.front = f.own } }
        else { f.modifiers = false }
        f.onWait = { await gate.wait() }
        let oldObserver = try #require(f.handlers.last)
        if library { f.model.usePrompt(copyOnly: false) } else { f.model.pasteSelected() }
        let oldTask = try #require(f.model.historyPasteTask)
        try await HistoryRequestPathTests().until { gate.entered }
        oldObserver(.sleep)
        #expect(!f.model.busy && f.model.historyPasteTask == nil && f.pairs.isEmpty)
        #expect(f.writes.count == (afterWrite ? 1 : 0))
        // Only a fresh explicit invocation may dispatch. A late old observer
        // and suspended task must not cancel it or replace its feedback.
        f.onActivate = nil; f.onWait = nil; f.modifiers = true
        f.delegate.closeHistory(); f.front = f.target; f.open()
        if library { f.model.library.open(f.entry) }
        oldObserver(.sleep)
        if library { f.model.usePrompt(copyOnly: false) } else { f.model.pasteSelected() }
        await f.finish()
        let feedback = f.model.statusMessage
        #expect(f.pairs.count == 1 && f.pairs.first?.0 == f.target)
        #expect(f.writes.count == (afterWrite ? 2 : 1))
        gate.release(); await oldTask.value
        #expect(f.pairs.count == 1 && f.writes.count == (afterWrite ? 2 : 1))
        #expect(f.model.statusMessage == feedback && !f.model.busy && f.model.historyPasteTask == nil)
    }
    @Test func modifiersWaitBeforeWriteIsBoundedAndCancellationStopsIt() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(); f.modifiers = false
        f.onWait = { if f.waits == 2 { f.modifiers = true } }
        f.model.pasteSelected(); await f.finish()
        #expect(f.waits == 2 && f.writes.count == 1 && f.pairs.count == 1)
        let g = try Fixture(); defer { g.clean() }; try await g.seed(); g.modifiers = false
        g.onWait = { g.delegate.closeHistory() }
        g.model.pasteSelected(); await g.finish()
        #expect(g.writes.isEmpty && g.pairs.isEmpty)
    }
    @Test func heldModifiersTimeoutHasNoWriteOrRetry() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed(); f.modifiers = false
        f.model.pasteSelected(); await f.finish()
        #expect(f.waits == 75 && f.writes.isEmpty && f.pairs.isEmpty)
        #expect(f.model.statusMessage?.contains("modifier keys are still held") == true)
    }
    @Test(arguments: ["permission", "board", "identity", "activation", "postingGate"])
    func finalFailureHasNoPairNoRetryAndTruthfulManualFallback(reason: String) async throws {
        let f = try Fixture(); defer { f.clean() }; f.open(); f.model.library.open(f.entry)
        switch reason {
        case "permission": f.onActivate = { f.permission = .unknown }
        case "board": f.onActivate = { f.boardVersion += 1 }
        case "identity": f.onActivate = { f.front = f.third }
        case "activation": f.activationSucceeds = false
        default: f.postFailure = .deliveryDisabled
        }
        f.model.usePrompt(copyOnly: false); await f.finish()
        #expect(f.writes.count == 1 && f.pairs.isEmpty)
        #expect(try await f.store.stats().count == 1)
        #expect(f.model.statusMessage?.contains("Paste was not requested") == true)
        if reason == "board" {
            #expect(f.model.statusMessage?.contains("clipboard changed") == true)
            #expect(f.model.statusMessage?.contains("Copy again") == true)
            #expect(f.model.statusMessage?.contains("⌘V") == false)
            #expect(f.model.statusMessage?.hasPrefix("Copied.") == false)
            // Only a new explicit Copy makes the selected payload current again.
            f.model.copySelected(); await f.finish()
            #expect(f.writes.count == 2 && f.pairs.isEmpty)
            #expect(f.model.statusMessage?.contains("Copied. Press ⌘V") == true)
        } else { #expect(f.model.statusMessage?.contains("manually") == true) }
        #expect(f.activations.count <= 1)
    }
    @Test(arguments: [true, false])
    func changedBoardFeedbackNeverClaimsSelectedPayloadIsCurrent(wrote: Bool) throws {
        let f = try Fixture(); defer { f.clean() }
        let message = f.model.pasteCoordinator.dependencies.feedback(.blocked(.boardChanged), wrote: wrote)
        #expect(message.contains("clipboard changed") && message.contains("Copy again"))
        #expect(!message.contains("⌘V") && !message.hasPrefix("Copied."))
        #expect(f.writes.isEmpty && f.pairs.isEmpty)
    }
    @Test(arguments: [true, false])
    func thirdAppObservedAfterWriteStopsBeforeAnyActivation(library: Bool) async throws {
        let f = try Fixture(); defer { f.clean() }
        f.onWrite = { f.front = f.third } // A live snapshot sees change before notification delivery.
        if library { f.open(); f.model.library.open(f.entry); f.model.usePrompt(copyOnly: false) }
        else { try await f.seed(); f.model.pasteSelected() }
        await f.finish()
        #expect(f.writes.count == 1 && f.activations.isEmpty && f.pairs.isEmpty)
        #expect(f.model.statusMessage?.contains("active app changed") == true)
        #expect(try await f.store.stats().count == 1)
    }
    @Test func consumedPasteCannotAutomaticallyRetryButExplicitCopyStillWorks() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.model.pasteSelected(); await f.finish()
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes.count == 1 && f.pairs.count == 1)
        f.model.copySelected(); await f.finish()
        #expect(f.writes.count == 2 && f.pairs.count == 1)
        #expect(try await f.store.stats().count == 1)
    }
    @Test func stalePrewriteWaitCannotWriteOrResetNewerLibraryForm() async throws {
        let gate = HistoryRequestPathTests.Gate()
        let f = try Fixture(); defer { gate.release(); f.clean() }; try await f.seed()
        f.modifiers = false; f.onWait = { await gate.wait() }
        f.model.pasteSelected(); let old = f.model.historyPasteTask
        try await HistoryRequestPathTests().until { gate.entered }
        f.delegate.closeHistory(); f.front = f.target; f.open(); f.modifiers = true
        f.model.library.open(f.entry); f.model.library.values["name"] = "new form"
        f.model.usePrompt(copyOnly: true); await f.finish()
        let feedback = f.model.statusMessage
        gate.release(); await old?.value
        #expect(f.writes == [.text("Hello new form 🧪\n")] && f.pairs.isEmpty)
        #expect(f.model.library.values["name"] == "new form" && f.model.library.screen == .use)
        #expect(f.model.statusMessage == feedback && !f.model.busy)
    }
    @Test func staleNativeRestoreCannotMutateNewFormOrFeedback() async throws {
        let gate = HistoryRequestPathTests.Gate()
        let f = try Fixture(); defer { gate.release(); f.clean() }; f.open(); f.model.library.open(f.entry)
        f.onActivate = { f.front = f.own }; f.onWait = { await gate.wait() }
        f.model.usePrompt(copyOnly: false); let old = f.model.historyPasteTask
        try await HistoryRequestPathTests().until { gate.entered }
        f.front = f.target; f.open(); f.model.library.open(f.entry)
        f.model.library.values["name"] = "new copy"
        f.model.usePrompt(copyOnly: true); await f.finish()
        let feedback = f.model.statusMessage
        gate.release(); await old?.value
        #expect(f.writes.count == 2 && f.pairs.isEmpty)
        #expect(f.model.library.values["name"] == "new copy" && f.model.library.screen == .use)
        #expect(f.model.statusMessage == feedback && f.delegate.recordingHistoryVisible)
        #expect(try await f.store.stats().count == 2)
    }
    @Test func defaultHistoryCombinedPayloadPreservesTextAndImageBytes() async throws {
        let f = try Fixture(); defer { f.clean() }
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z/D/PwAG/gL+DHWJ3gAAAABJRU5ErkJggg=="))
        _ = try await f.store.capture(CapturePayload(text: "Synthetic image label", imageData: png), limits: .init())
        await f.model.refresh(); f.open()
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes == [.textAndImage("Synthetic image label", Array(png))])
        #expect(f.pairs.count == 1 && f.pairs.first?.0 == f.target)
        #expect(try await f.store.stats().count == 1)
    }
    @Test func sourceOnlyDefaultDoesNotAccessPlatformAndCannotProduceEffects() async throws {
        let f = try Fixture(); defer { f.clean() }
        let model = AppModel(store: f.store, demo: false, preferenceStore: f.defaults)
        let delegate = AppDelegate(historyRecordingModel: model)
        model.start(); model.startRecording(); model.registerHotkey()
        delegate.toggleHistory(); model.library.open(f.entry)
        model.usePrompt(copyOnly: false); await model.historyPasteTask?.value
        #expect(try await f.store.stats().count == 0)
        model.usePrompt(copyOnly: true); await model.historyPasteTask?.value
        #expect(try await f.store.stats().count == 0)
        #expect(!NativeIntegrationGates.appLaunchEnabled && !NativeIntegrationGates.platformAccessEnabled && !NativeIntegrationGates.realPostingEnabled)
        #expect(!PasteCoordinator.accessibilityGranted)
        model.stop()
    }
    @Test func loginDefaultOffPreservesExistingRegistrationAndSavedPreferences() throws {
        #expect(!OnboardingDefaults.launchAtLogin)
        #expect(!OnboardingDefaults.initialLogin(existingRegistration: false))
        #expect(OnboardingDefaults.initialLogin(existingRegistration: true))
        #expect(OnboardingDefaults.registrationChange(selected: false, wasChanged: false) == nil)
        #expect(OnboardingDefaults.registrationChange(selected: true, wasChanged: false) == true)
        #expect(OnboardingDefaults.registrationChange(selected: false, wasChanged: true) == false)
        #expect(OnboardingDefaults.registrationChange(selected: true, wasChanged: true) == true)
        let f = try Fixture(); defer { f.clean() }
        f.defaults.set("existing-value", forKey: "syntheticExistingPreference")
        f.model.finishOnboarding(launchAtLogin: false)
        #expect(f.defaults.string(forKey: "syntheticExistingPreference") == "existing-value")
        #expect(f.model.onboardingComplete)
    }
    @Test(arguments: [false, true])
    func presentationDiagnosticsKeepMenuOwnershipAndPrivacy(record: Bool) throws {
        let f = try Fixture(); defer { f.clean() }
        var records: [HistoryPresentationDiagnostics.Record] = []
        f.delegate.configureHistoryDiagnostics(HistoryPresentationDiagnostics(now: { 123 }, sink: record ? { records.append($0) } : nil))
        let ticket = f.delegate.beginContextMenuInvocation()!
        let generation = f.delegate.currentContextMenuGeneration!
        f.delegate.openContextMenuInvocation(ticket: ticket, generation: UUID())
        f.delegate.openContextMenuInvocation(ticket: ticket, generation: generation)
        f.delegate.finishContextMenuInvocation(ticket: ticket, generation: generation)
        #expect(f.delegate.recordingHistoryVisible)
        for handler in f.handlers { handler(.activated(f.own)) }
        f.delegate.observeHistoryRecording(.spaceChanged)
        f.delegate.openHistory(capturedInvocation: ticket)
        f.delegate.closeHistory(reason: "/private/Synthetic secret")
        #expect(!f.delegate.recordingHistoryVisible && f.writes.isEmpty && f.activations.isEmpty && f.pairs.isEmpty)
        if record {
            #expect(records.contains { $0.event == .ignoredOwnActivation && $0.requestGeneration == ticket.generation })
            #expect(records.contains { $0.event == .openGuard && $0.reason == .generationMismatch })
            #expect(records.contains { $0.event == .openGuard && $0.reason == .accepted })
            #expect(records.contains { $0.event == .finishMenu && $0.reason == .accepted })
            #expect(records.contains { $0.event == .requestObservation && $0.reason == .spaceChanged && $0.valid == false })
            #expect(records.contains { $0.event == .closeRequested && $0.reason == .explicitClose })
            #expect(records.allSatisfy { !$0.line.contains("Synthetic secret") && !$0.line.contains("synthetic.target") && !$0.line.contains("/synthetic/") })
        } else { #expect(records.isEmpty) }
    }

    @Test(arguments: ["stale", "lifecycle", "invalid", "cancel", "hide"])
    func presentationDiagnosticGuardReasons(scenario: String) throws {
        let f = try Fixture(); defer { f.clean() }
        var records: [HistoryPresentationDiagnostics.Record] = []
        f.delegate.configureHistoryDiagnostics(.init(now: { 1 }, sink: { records.append($0) }))
        let ticket = f.delegate.beginContextMenuInvocation()!
        let generation = f.delegate.currentContextMenuGeneration!
        let expected: HistoryPresentationDiagnostics.Reason
        switch scenario {
        case "stale":
            _ = f.delegate.beginContextMenuInvocation()
            f.delegate.openContextMenuInvocation(ticket: ticket, generation: generation)
            expected = .ticketMismatch
        case "lifecycle":
            f.model.stop(); f.delegate.openHistory(capturedInvocation: ticket)
            expected = .lifecycle
        case "invalid":
            f.delegate.observeHistoryRecording(.spaceChanged, ticket: ticket)
            f.delegate.openContextMenuInvocation(ticket: ticket, generation: generation)
            expected = .invalidRequest
        case "hide":
            f.delegate.hideContextMenuInvocation(ticket: ticket, generation: generation)
            f.delegate.finishContextMenuInvocation(ticket: ticket, generation: generation)
            expected = .hideChoice
        default:
            f.delegate.finishContextMenuInvocation(ticket: ticket, generation: generation)
            expected = .noOpenChoice
        }
        #expect(records.contains { $0.reason == expected })
        #expect(!f.delegate.recordingHistoryVisible && f.writes.isEmpty && f.activations.isEmpty && f.pairs.isEmpty)
    }

}
