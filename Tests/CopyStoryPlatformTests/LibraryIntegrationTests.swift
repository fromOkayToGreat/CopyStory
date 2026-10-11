import AppKit
import Dispatch
import Testing
import CopyStoryCore
@testable import CopyStory

/// Synthetic content, isolated preferences, named pasteboards, and no paste destination.
@Suite(.serialized)
struct LibraryIntegrationTests {
    @MainActor private final class Fixture {
        let root: URL
        let suite = "CopyStory.LibraryTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let board = NSPasteboard.withUniqueName()
        let model: AppModel
        init(failWrite: Bool = false, demo: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CopyStory-LibraryIntegration-\(UUID().uuidString)")
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: "onboardingComplete")
            model = AppModel(store: try HistoryStore(directory: root), demo: demo, preferenceStore: defaults)
            model.monitor = ClipboardMonitor(onCapture: { [weak model] in model?.save($0) }, onStatus: { _ in }, pasteboard: board,
                                             writeItems: failWrite ? { _ in false } : nil)
            model.monitor.start()
        }
        func clean() {
            model.stop(); board.releaseGlobally(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var entry: LibraryEntry {
            LibraryEntry(title: "Explain", template: "Explain {{topic}} in a {{tone}} tone.", variables: [
                .init(name: "topic", defaultValue: "Photosynthesis"),
                .init(name: "tone", kind: .dropdown, defaultValue: "Friendly", options: ["Friendly", "Concise"])
            ])
        }
    }
    @MainActor private func idle(_ model: AppModel) async throws {
        for _ in 0..<1000 {
            if !model.busy { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Prompt action did not finish")
    }
    @MainActor private func saved(_ library: LibraryModel) async throws {
        for _ in 0..<1000 {
            if !library.saving { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Library save did not finish")
    }

    @Test @MainActor func copyIterationsPersistExactOutputOnceAndResetDefaults() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = try #require(f.model.library.store)
        let entry = f.entry
        try await store.create(entry)
        f.model.library.open(entry)
        f.model.library.values["topic"] = "Café\n日本語"
        f.model.library.values["tone"] = "Concise"
        f.model.usePrompt(copyOnly: true); try await idle(f.model)
        let expected = "Explain Café\n日本語 in a Concise tone."
        #expect(f.board.string(forType: .string) == expected)
        #expect(f.model.library.screen == .use)
        f.model.monitor.poll()
        f.model.usePrompt(copyOnly: true); try await idle(f.model)
        let rows = try await f.model.store.search(query: "", filter: .all)
        #expect(rows.count == 1)
        #expect(rows.first?.sourceApp == "CopyStory")
        #expect(try await f.model.store.fullText(id: rows[0].id) == expected)
        #expect(try await store.entry(id: entry.id)?.defaultValues == entry.defaultValues)
        f.model.library.back(); f.model.library.open(entry)
        #expect(f.model.library.values == entry.defaultValues)
    }

    @Test @MainActor func pasteFallbackCopiesAndRecordsWithoutPostingPaste() async throws {
        let f = try Fixture(); defer { f.clean() }
        f.model.library.open(f.entry)
        var closed = false
        f.model.closePanel = { closed = true }
        // No destination is remembered, so the coordinator cannot emit a paste event.
        f.model.usePrompt(copyOnly: false); try await idle(f.model)
        #expect(closed)
        #expect(f.board.string(forType: .string) == "Explain Photosynthesis in a Friendly tone.")
        #expect(try await f.model.store.stats().count == 1)
        #expect(f.model.statusMessage?.contains("Copied.") == true)
    }

    @Test(arguments: ["paused", "locked", "stopped", "excluded", "demo"])
    @MainActor func recordingPoliciesApplyToCompletedPrompts(policy: String) async throws {
        let f = try Fixture(demo: policy == "demo"); defer { f.clean() }
        switch policy {
        case "paused": f.model.paused = true
        case "locked": f.model.isLocked = true
        case "stopped": f.model.monitor.stop()
        case "excluded": f.model.setExcludedApps([Bundle.main.bundleIdentifier ?? "app.copystory"])
        default: break
        }
        f.model.library.open(f.entry)
        f.model.usePrompt(copyOnly: true); try await idle(f.model)
        #expect(try await f.model.store.stats().count == 0)
        #expect((f.board.string(forType: .string) != nil) == (policy != "demo"))
    }

    @Test @MainActor func failedClipboardWriteAndCanceledSelectionDoNotEnterHistory() async throws {
        let f = try Fixture(failWrite: true); defer { f.clean() }
        f.model.library.open(f.entry)
        f.model.usePrompt(copyOnly: false); try await idle(f.model)
        #expect(try await f.model.store.stats().count == 0)
        #expect(f.model.statusMessage?.contains("could not write") == true)
        let good = try Fixture(); defer { good.clean() }
        good.model.library.open(good.entry)
        good.model.usePrompt(copyOnly: true)
        good.model.cancelPendingSelection()
        try await idle(good.model)
        #expect(good.board.string(forType: .string) == nil)
        #expect(try await good.model.store.stats().count == 0)
    }

    @Test @MainActor func capacityFailureLeavesCopiedTextAndClearDoesNotRecaptureIt() async throws {
        let f = try Fixture(); defer { f.clean() }
        _ = try await f.model.store.capture(CapturePayload(text: "keep pinned"), limits: .init())
        let pinned = try #require(try await f.model.store.search(query: "", filter: .all).first)
        try await f.model.store.setPinned(id: pinned.id, pinned: true)
        f.model.maxItems = 1
        f.model.library.open(f.entry)
        f.model.usePrompt(copyOnly: true); try await idle(f.model)
        #expect(f.board.string(forType: .string) != nil)
        #expect(f.model.statusMessage?.contains("history is full") == true)
        #expect(try await f.model.store.stats().count == 1)
        await f.model.clear(includePinned: true).value
        f.model.monitor.poll()
        #expect(try await f.model.store.stats().count == 0)
    }

    @Test @MainActor func saveFromHistoryUsesFullTextAndLibraryFailureDoesNotDisableHistory() async throws {
        let f = try Fixture(); defer { f.clean() }
        let text = String(repeating: "long text ", count: 100) + "{{topic}}"
        await f.model.save(CapturePayload(text: text)).value
        let item = try #require(f.model.items.first)
        #expect(item.hasText && item.preview != text)
        f.model.saveToLibrary(item); try await idle(f.model)
        #expect(f.model.library.draft?.template == text)
        #expect(f.model.library.draft?.variables.map(\.name) == ["topic"])
        #expect(try await f.model.store.stats().count == 1)
        f.model.library.saveDraft(); try await saved(f.model.library)
        await f.model.clear(includePinned: true).value
        #expect(try await f.model.library.store?.search(query: "").count == 1)
        let blocked = f.root.appendingPathComponent("bad-library")
        try Data("a regular file".utf8).write(to: blocked)
        let unavailable = LibraryModel(directory: blocked)
        #expect(unavailable.store == nil && unavailable.errorMessage != nil)
        await f.model.save(CapturePayload(text: "history still works")).value
        #expect(try await f.model.store.stats().count == 1)
    }

    @Test @MainActor func dirtyDismissAndFailedSaveRetainDraft() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = try #require(f.model.library.store), entry = f.entry
        try await store.create(entry)
        f.model.library.edit(entry)
        f.model.library.draft?.title = "Changed"
        var dismissed = false
        f.model.library.requestDismiss { dismissed = true }
        #expect(f.model.library.confirmDiscard && !dismissed)
        f.model.library.cancelDiscard()
        #expect(f.model.library.draft?.title == "Changed")
        try await store.delete(id: entry.id)
        f.model.library.saveDraft(); try await saved(f.model.library)
        #expect(f.model.library.draft?.title == "Changed")
        #expect(f.model.library.errorMessage?.contains("draft is still here") == true)
        f.model.library.requestDismiss { dismissed = true }
        f.model.library.discardChanges()
        #expect(dismissed && f.model.library.screen == .browse)
    }

    @Test @MainActor func acceptedLibrarySaveDrainsAtTermination() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = try #require(f.model.library.store)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            Task.detached { await store.blockForLibraryTest(started: { started.resume() }, release: release) }
        }
        f.model.library.edit()
        f.model.library.draft?.title = "Accepted"
        f.model.library.setTemplate("persist before quit")
        f.model.library.saveDraft()
        let drain = f.model.prepareForTermination()
        var done = false
        let waiter = Task { await drain.value; done = true }
        await Task.yield()
        #expect(!done)
        release.signal(); await waiter.value
        #expect(try await store.search(query: "").map(\.title) == ["Accepted"])
        f.model.library.edit()
        #expect(f.model.library.screen == .browse)
    }

    @Test @MainActor func clipboardAdmissionPrecedesClearAndFailedWritesHaveNoCallback() async throws {
        let f = try Fixture(); defer { f.clean() }
        let payload = CapturePayload(text: "synthetic completed prompt", sourceApp: "CopyStory")
        var clear: Task<Void, Never>?
        var wrote = false
        _ = await f.model.pasteCoordinator.paste(using: f.model.monitor, payload: payload, closePanel: {
            #expect(wrote, "Admission must occur before closing or focus restoration can suspend.")
            clear = f.model.clear(includePinned: true)
        }, onClipboardWrite: {
            wrote = true
            f.model.recordCompletedPrompt(payload)
        })
        await clear?.value
        #expect(try await f.model.store.stats().count == 0)
        let failed = try Fixture(failWrite: true); defer { failed.clean() }
        var failedCallback = false, failedClose = false
        _ = await failed.model.pasteCoordinator.paste(using: failed.model.monitor, payload: payload,
            closePanel: { failedClose = true }, onClipboardWrite: { failedCallback = true })
        #expect(!failedCallback && !failedClose)
    }

    @Test @MainActor func rapidFavoriteTogglesAndSharedSearchRemainConsistent() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = try #require(f.model.library.store), entry = f.entry
        try await store.create(entry)
        f.model.library.toggleFavorite(entry)
        f.model.library.toggleFavorite(entry)
        await f.model.library.waitForPendingWrites()
        #expect(try await store.entry(id: entry.id)?.isFavorite == false)
        f.model.query = "Explain"
        f.model.selectSection(.library)
        #expect(f.model.library.query == "Explain")
        f.model.selectSection(.history)
        #expect(f.model.query == "Explain")
    }
}

private extension LibraryStore {
    func blockForLibraryTest(started: @Sendable () -> Void, release: DispatchSemaphore) {
        started(); #expect(release.wait(timeout: .now() + 5) == .success)
    }
}
