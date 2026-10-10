import AppKit
import Dispatch
import Testing
import CopyStoryCore
@testable import CopyStory

@Suite(.serialized)
struct TerminationTests {
    @MainActor
    @Test(arguments: ["pin", "delete", "limits"])
    func quitWaitsForAcceptedPinDeleteAndLimits(operation: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-Termination-\(UUID().uuidString)")
        let suite = "CopyStory.TerminationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try HistoryStore(directory: directory)
        _ = try await store.capture(CapturePayload(text: "first", capturedAt: Date(timeIntervalSince1970: 1)), limits: HistoryLimits())
        _ = try await store.capture(CapturePayload(text: "second", capturedAt: Date(timeIntervalSince1970: 2)), limits: HistoryLimits())
        let first = try #require(try await store.search(query: "first", filter: .all).first)
        let model = AppModel(store: store, demo: true, preferenceStore: defaults)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.monitor = ClipboardMonitor(onCapture: { _ in }, onStatus: { _ in }, pasteboard: board)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            Task.detached { await store.blockForTerminationTest(started: { started.resume() }, release: release) }
        }
        switch operation {
        case "pin": model.togglePin(first)
        case "delete": model.delete(first)
        default: model.applyLimits(items: 1, megabytes: 10)
        }
        let drain = model.prepareForTermination()
        var finished = false
        let waiter = Task { await drain.value; finished = true }
        await Task.yield()
        #expect(!finished)
        // Late UI actions must not enter the queue after its shutdown boundary.
        model.delete(first)
        model.togglePin(first)
        model.applyLimits(items: 9, megabytes: 90)
        release.signal()
        await waiter.value
        let rows = try await store.search(query: "", filter: .all)
        if operation == "pin" {
            #expect(rows.count == 2)
            #expect(rows.first(where: { $0.id == first.id })?.isPinned == true)
        } else {
            #expect(rows.map(\.preview) == ["second"])
        }
        #expect(model.maxItems == (operation == "limits" ? 1 : 1000))
    }

    @MainActor
    @Test(arguments: [false, true])
    func quitWaitsForAcceptedSaveAndClear(clear: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-Termination-\(UUID().uuidString)")
        let suite = "CopyStory.TerminationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try HistoryStore(directory: directory)
        let model = AppModel(store: store, demo: true, preferenceStore: defaults)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.monitor = ClipboardMonitor(onCapture: { _ in }, onStatus: { _ in }, pasteboard: board)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            Task.detached { await store.blockForTerminationTest(started: { started.resume() }, release: release) }
        }
        model.save(CapturePayload(text: "accepted before quit"))
        if clear { model.clear(includePinned: true) }
        let drain = model.prepareForTermination()
        var finished = false
        let waiter = Task { await drain.value; finished = true }
        await Task.yield()
        #expect(!finished, "Quit must wait while an accepted mutation is blocked.")
        await model.save(CapturePayload(text: "after quit began")).value
        release.signal()
        await waiter.value
        #expect(finished)
        let rows = try await store.search(query: "", filter: .all)
        #expect(rows.map(\.preview) == (clear ? [] : ["accepted before quit"]))
        #expect(try await store.stats().count == (clear ? 0 : 1))
    }
}

private extension HistoryStore {
    func blockForTerminationTest(started: @Sendable () -> Void, release: DispatchSemaphore) {
        started()
        #expect(release.wait(timeout: .now() + 5) == .success)
    }
}
