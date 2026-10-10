import Foundation
import Dispatch
import Testing
import CopyStoryCore
@testable import CopyStory

/// These tests never start monitoring, register hotkeys/login items, write the
/// general clipboard, or request permissions. Demo mode makes successful
/// selection observable through feedback without performing the external action.
@Suite(.serialized)
struct AppModelTests {
    @MainActor
    @Test func testDebouncePreventsActionsOnPreviousSearchResults() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try await add("alpha previous result", to: store, date: 20)
        try await add("beta desired result", to: store, date: 10)
        let model = AppModel(store: store, demo: true)
        await model.refresh()
        let previous = try #require(model.selectedItem)
        #expect(previous.preview == "alpha previous result")

        model.query = "beta"
        #expect(model.isSearching)
        // All selection entry points must refuse stale rows synchronously,
        // including a context-menu/mouse action holding the previous item.
        model.pasteSelected()
        model.paste(previous)
        model.copySelected()
        #expect(!model.busy)
        #expect(model.statusMessage == nil)

        try await waitUntil { !model.isSearching }
        #expect(model.items.map(\.preview) == ["beta desired result"])
        #expect(model.selectedItem?.preview == "beta desired result")
        model.pasteSelected()
        try await waitUntil { !model.busy }
        #expect(model.statusMessage?.hasPrefix("Preview mode: pasting is disabled.") == true,
                "Once current results are ready, selection must become available again.")
    }

    @MainActor
    @Test func testClosingPanelCancelsSelectionBeforePayloadLookupCompletes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try await add("synthetic pending paste", to: store, date: 1)
        let model = AppModel(store: store, demo: true)
        await model.refresh()

        // Hold the storage actor so the request cannot finish its payload
        // lookup until after the user closes/reopens the panel. This avoids
        // assuming that disk access will be slow enough to expose the race.
        let release = DispatchSemaphore(value: 0)
        var blocker: Task<Void, Never>?
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            blocker = Task.detached {
                await store.blockRequestsForAppModelTest(started: { started.resume() }, release: release)
            }
        }
        defer { release.signal() }

        model.pasteSelected()
        #expect(model.busy)
        await Task.yield()
        #expect(model.statusMessage == nil)
        model.cancelPendingSelection()
        release.signal()
        await blocker?.value
        try await waitUntil { !model.busy }
        #expect(model.statusMessage == nil,
                "A dismissed selection must produce neither paste feedback nor a demo action.")

        // Cancellation invalidates the pending request rather than permanently
        // disabling history; a later deliberate selection still works.
        model.pasteSelected()
        try await waitUntil { !model.busy }
        #expect(model.statusMessage?.hasPrefix("Preview mode: pasting is disabled.") == true)
    }

    @MainActor
    @Test func testCanceledMissingPayloadDoesNotEmitDelayedErrorFeedback() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try await add("synthetic soon-unavailable item", to: store, date: 1)
        let model = AppModel(store: store, demo: true)
        await model.refresh()
        let selected = try #require(model.selectedID)
        // Simulate pruning/removal between displaying a result and requesting
        // its payload. The model intentionally still displays the stale row.
        try await store.delete(id: selected)

        model.pasteSelected()
        #expect(model.busy)
        model.cancelPendingSelection()
        try await waitUntil { !model.busy }
        #expect(model.statusMessage == nil,
                "Cancellation must suppress failure-path feedback as well as success-path actions.")
    }

    @MainActor
    @Test func testSelectionSurvivesRefreshAndMovesWhenFilteredOut() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try await add("alpha selected", to: store, date: 20)
        try await add("beta pinned", to: store, date: 10)
        let betaResults = try await store.search(query: "beta", filter: .all)
        let beta = try #require(betaResults.first)
        try await store.setPinned(id: beta.id, pinned: true)
        let model = AppModel(store: store, demo: true)
        await model.refresh()
        let selected = try #require(model.selectedID)

        try await add("gamma newly copied", to: store, date: 30)
        await model.refresh()
        #expect(model.items.first?.preview == "gamma newly copied")
        #expect(model.selectedID == selected, "New captures should not move the user's selection.")

        model.query = "alpha"
        try await waitUntil { !model.isSearching }
        #expect(model.selectedID == selected)

        // Two changes inside the debounce window must publish only the latest
        // query/filter combination, with a selection actually present in it.
        model.query = ""
        model.filter = .pinned
        try await waitUntil { !model.isSearching }
        #expect(model.items.map(\.id) == [beta.id])
        #expect(model.selectedID == beta.id)

        model.filter = .images
        try await waitUntil { !model.isSearching }
        #expect(model.items.isEmpty)
        #expect(model.selectedID == nil)
        model.pasteSelected()
        #expect(!model.busy)
        #expect(model.statusMessage == nil)
    }

    @MainActor
    @Test func testPagingReachesRecordsBeyondStoreBatchLimit() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let fixtureCount = 1_005
        let limits = HistoryLimits(maxItems: 2_000, maxBytes: 20_000_000)
        for index in 0..<fixtureCount {
            let outcome = try await store.capture(
                CapturePayload(text: "synthetic page item \(index)",
                               capturedAt: Date(timeIntervalSince1970: Double(index))),
                limits: limits)
            try #require(outcome == .saved)
        }
        let model = AppModel(store: store, demo: true)
        await model.refresh()
        #expect(model.items.count == 100)
        #expect(model.hasMore)
        let selected = try #require(model.selectedID)

        for expectedCount in stride(from: 200, through: 1_000, by: 100) {
            model.loadMore()
            try await waitUntil { model.items.count == expectedCount }
            #expect(model.hasMore,
                    "The next-page sentinel must survive the store's 1,000-row query cap.")
            #expect(model.selectedID == selected)
        }
        model.loadMore()
        try await waitUntil { model.items.count == fixtureCount }
        #expect(!model.hasMore)
        #expect(Set(model.items.map(\.id)).count == fixtureCount)
        #expect(model.items.first?.preview == "synthetic page item 1004")
        #expect(model.items.last?.preview == "synthetic page item 0")
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("CopyStory-AppModelTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func add(_ text: String, to store: HistoryStore, date: Double) async throws {
        let outcome = try await store.capture(CapturePayload(text: text, capturedAt: Date(timeIntervalSince1970: date)),
                                              limits: HistoryLimits())
        try #require(outcome == .saved)
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try #require(predicate(), "AppModel did not settle within the bounded test interval.")
    }
}

private extension HistoryStore {
    /// A test-only actor operation. Blocking is bounded and happens off the
    /// main actor; it simulates an in-progress store operation deterministically.
    func blockRequestsForAppModelTest(started: @Sendable () -> Void, release: DispatchSemaphore) {
        started()
        _ = release.wait(timeout: .now() + 5)
    }
}
