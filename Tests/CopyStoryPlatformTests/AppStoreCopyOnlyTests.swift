#if COPYSTORY_PRODUCTION
import Foundation
import Testing
import CopyStoryCore
@testable import CopyStory

// Actual production compile selection, with injected clipboard/focus/event sinks.
// No app start, permissions, login registration, general-board reads/writes or events.
@Suite(.serialized) @MainActor
struct AppStoreCopyOnlyTests {
    typealias Fixture = NativeSourceIntegrationTests.Fixture

    @Test(arguments: [false, true])
    func staleOptInAndRepeatedReuseAreCopyOnly(library: Bool) async throws {
        let f = try Fixture(optIn: false); defer { f.clean() }
        f.defaults.set(true, forKey: "directPasteEnabled")
        f.model.stop()
        f.model = AppModel(store: f.store, demo: false, preferenceStore: f.defaults,
            nativeEnvironment: f.environment, developmentDefaults: false)
        #expect(!AppDistribution.directPasteAvailable && AppDistribution.historyActionLabel == "Copy")
        #expect(!NativeIntegrationGates.postingConsentEnabled && !NativeIntegrationGates.realPostingEnabled)
        #expect(!f.model.directPasteEnabled)
        f.model.setDirectPasteEnabled(true)
        #expect(!f.model.directPasteEnabled)
        #expect(f.defaults.bool(forKey: "directPasteEnabled")) // Ignored, never reset unrelated user data.
        // Copy needs neither a target nor permission, including when secure input is active elsewhere.
        f.front = nil; f.permission = .unknown; f.secureInput = true
        _ = try await f.store.capture(CapturePayload(text: "Synthetic copy-only history"), limits: .init())
        await f.model.refresh()
        for _ in 0..<3 {
            if library {
                f.model.library.section = .library
                f.model.library.open(f.entry)
                #expect(f.model.handleLibraryCommandReturn())
            } else { f.model.pasteSelected() } // Return/double-click action retained as Copy.
            await f.finish()
            #expect(!f.model.busy && f.model.historyPasteTask == nil)
        }
        #expect(f.writes.count == 3)
        #expect(f.activations.isEmpty && f.pairs.isEmpty && f.waits == 0)
        #expect(try await f.store.search(query: "Synthetic copy-only history", filter: .all).count == 1)
        #expect(f.model.shortcutCode == DefaultShortcut.keyCode)
        #expect(f.model.shortcutModifiers == DefaultShortcut.modifiers)
    }

    @Test func interruptedHistoryLoadCannotWriteAndCanRetry() async throws {
        // Cancel before the async payload lookup resumes. A fresh explicit
        // action must complete with no posting.
        let f = try Fixture(optIn: false); defer { f.clean() }
        _ = try await f.store.capture(CapturePayload(text: "Synthetic interrupted copy"), limits: .init())
        await f.model.refresh()
        f.model.pasteSelected()
        f.model.cancelPendingSelection() // Before async payload load resumes.
        await f.finish()
        #expect(f.writes.isEmpty && !f.model.busy)
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes == [.text("Synthetic interrupted copy")])
        #expect(f.activations.isEmpty && f.pairs.isEmpty)
    }

    @Test func deniedClipboardWriteDoesNotActivatePostOrRemainBusy() async throws {
        let f = try Fixture(optIn: false); defer { f.clean() }
        _ = try await f.store.capture(CapturePayload(text: "Synthetic failure"), limits: .init())
        await f.model.refresh()
        f.writeSucceeds = false
        f.model.pasteSelected(); await f.finish()
        #expect(!f.model.busy && f.model.historyPasteTask == nil)
        #expect(f.activations.isEmpty && f.pairs.isEmpty)
        f.writeSucceeds = true
        f.model.pasteSelected(); await f.finish()
        #expect(f.writes.count == 2 && !f.model.busy)
    }
}
#endif
