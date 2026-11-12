import AppKit
import Foundation
import Testing
import CopyStoryCore
@testable import CopyStory

// Only temporary stores/preferences and synthetic key events; no GUI, app start,
// real clipboard, permission, login or global shortcut effects.
@Suite(.serialized) @MainActor
struct ListDeletionTests {
    @MainActor final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-ListDeletion-\(UUID())")
        let suite = "CopyStory.ListDeletion.\(UUID())"
        let preferences: UserDefaults
        let model: AppModel
        let library: Bool
        init(library: Bool) throws {
            self.library = library
            preferences = UserDefaults(suiteName: suite)!
            model = AppModel(store: try HistoryStore(directory: root), demo: true, preferenceStore: preferences)
            model.library.section = library ? .library : .history
        }
        var ids: [String] { library ? model.library.items.map(\.id) : model.items.map(\.id) }
        var selectedID: String? {
            get { library ? model.library.selectedID : model.selectedID }
            set { if library { model.library.selectedID = newValue } else { model.selectedID = newValue } }
        }
        func seed(_ count: Int = 5) async throws {
            for i in 0..<count {
                let text = "Fixture \(i % 2 == 0 ? "match" : "other") \(i)"
                _ = try await model.store.capture(CapturePayload(text: text, capturedAt: Date(timeIntervalSince1970: Double(i))), limits: .init())
                try await model.library.store!.create(LibraryEntry(title: text, template: text, isFavorite: i % 2 == 0))
            }
            await refresh()
        }
        func refresh() async { if library { await model.library.refresh() } else { await model.refresh() } }
        func key(code: UInt16 = 51, flags: NSEvent.ModifierFlags = [], repeating: Bool = false,
                 responder: NSResponder? = NSView()) throws -> Bool {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: repeating, keyCode: code))
            return library ? model.library.handleDeletionKey(event, responder: responder)
                : model.handleHistoryDeletionKey(event, responder: responder)
        }
        func settle() async throws {
            if library { await model.library.waitForPendingWrites() }
            else {
                for _ in 0..<10000 {
                    if !model.historyDeletionBusy { break }
                    await Task.yield()
                }
                try #require(!model.historyDeletionBusy)
            }
        }
        func confirmAndSettle() async throws {
            if library {
                let entry = try #require(model.library.pendingDelete)
                #expect(try await model.library.store!.entry(id: entry.id) != nil) // Confirmation is a safeguard, not deletion.
                model.library.delete(entry); model.library.pendingDelete = nil
            }
            try await settle()
        }
        func clean() {
            _ = model.prepareForTermination()
            model.stop()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test(arguments: [false, true], [0, 2, 4])
    func firstMiddleLastFollowVisibleOrder(library: Bool, index: Int) async throws {
        let f = try Fixture(library: library); defer { f.clean() }; try await f.seed()
        let before = f.ids
        f.selectedID = before[index]
        #expect(try f.key(code: index == 2 ? 117 : 51))
        try await f.confirmAndSettle()
        #expect(f.ids == before.filter { $0 != before[index] })
        #expect(f.selectedID == before[index == before.count - 1 ? index - 1 : index + 1])
        if !library { #expect(f.model.historyDeletion?.item.id == before[index]) }
        let neighbor = f.selectedID
        // Refresh/reopen and return from the other section must retain the neighbor.
        let delegate = AppDelegate(historyRecordingModel: f.model)
        delegate.toggleHistory(); delegate.toggleHistory(); delegate.toggleHistory()
        f.model.selectSection(library ? .history : .library)
        f.model.selectSection(library ? .library : .history)
        await f.refresh()
        #expect(f.selectedID == neighbor)
    }

    @Test(arguments: [false, true])
    func repeatedDeletionReachesPrecedingThenEmpty(library: Bool) async throws {
        let f = try Fixture(library: library); defer { f.clean() }; try await f.seed(4)
        let before = f.ids
        f.selectedID = before[1]
        for (removed, next) in [(before[1], before[2]), (before[2], before[3]), (before[3], before[0])] {
            #expect(f.selectedID == removed)
            #expect(try f.key())
            try await f.confirmAndSettle()
            #expect(f.selectedID == next)
        }
        #expect(try f.key(code: 117, flags: .function))
        try await f.confirmAndSettle()
        #expect(f.ids.isEmpty && f.selectedID == nil)
        #expect(try !f.key())
        await f.refresh()
        #expect(f.selectedID == nil)
    }

    @Test(arguments: [false, true])
    func searchAndFavoritesUseDisplayedOrder(library: Bool) async throws {
        let f = try Fixture(library: library); defer { f.clean() }; try await f.seed(7)
        if library { f.model.library.query = "match"; f.model.library.favoritesOnly = true }
        else {
            f.model.query = "match"
            for item in f.model.items where item.preview.contains("match") { try await f.model.store.setPinned(id: item.id, pinned: true) }
            f.model.filter = .pinned
        }
        await f.refresh()
        let before = f.ids
        try #require(before.count == 4)
        f.selectedID = before[1]
        #expect(try f.key(flags: .command)) // Existing Command-Backspace shortcut remains.
        try await f.confirmAndSettle()
        #expect(f.selectedID == before[2])
        #expect(f.ids == before.filter { $0 != before[1] })
        if library { f.model.library.query = ""; f.model.library.favoritesOnly = false }
        else { f.model.query = ""; f.model.filter = .all }
        await f.refresh()
        #expect(f.ids.count == 6 && f.selectedID == before[2])
    }

    @Test(arguments: [false, true])
    func lastDisplayedRowChoosesPrecedingDespiteAnotherPage(library: Bool) async throws {
        let f = try Fixture(library: library); defer { f.clean() }; try await f.seed(102)
        let before = f.ids
        try #require(before.count == 100)
        f.selectedID = before[99]
        #expect(try f.key())
        try await f.confirmAndSettle()
        #expect(f.ids.count == 100 && f.selectedID == before[98])
    }

    @Test(arguments: [false, true])
    func userSelectionDuringDeletionIsPreserved(library: Bool) async throws {
        let f = try Fixture(library: library); defer { f.clean() }; try await f.seed(4)
        let before = f.ids
        f.selectedID = before[1]
        #expect(try f.key())
        if library {
            f.model.library.delete(try #require(f.model.library.pendingDelete))
            f.model.library.pendingDelete = nil
        }
        f.selectedID = before[0] // A new user action wins over the captured neighbor.
        try await f.settle()
        #expect(f.selectedID == before[0] && f.ids.count == 3)
    }

    final class ComposingEditor: NSTextView {
        override func hasMarkedText() -> Bool { true }
    }
    @Test(arguments: [false, true])
    func editorCompositionRepeatAndSearchCannotDelete(library: Bool) async throws {
        let f = try Fixture(library: library); defer { f.clean() }; try await f.seed(2)
        let before = f.ids
        for responder: NSResponder in [NSTextField(), NSTextView(), ComposingEditor()] {
            for code: UInt16 in [51, 117] {
                #expect(try !f.key(code: code, responder: responder))
                #expect(try !f.key(code: code, flags: .command, responder: responder))
            }
        }
        #expect(try f.key(repeating: true))
        #expect(try f.key(code: 117, flags: .function, repeating: true))
        #expect(f.model.library.pendingDelete == nil && f.model.historyDeletion == nil)
        if library { f.model.library.query = "match" } else { f.model.query = "match" }
        #expect(try !f.key()) // Search is in flight; no stale-row deletion.
        #expect(f.ids == before)
        await f.refresh()
        if library {
            f.model.library.open(try #require(f.model.library.selected))
            #expect(try !f.key())
            f.model.library.edit(try #require(f.model.library.selected))
            #expect(try !f.key())
        }
    }

    @Test func libraryCancellationAndDuplicateConfirmKeepSafeguards() async throws {
        let f = try Fixture(library: true); defer { f.clean() }; try await f.seed(3)
        let before = f.ids
        f.selectedID = before[1]
        #expect(try f.key())
        #expect(try !f.key()) // Pending confirmation cannot be replaced by a second key.
        f.model.library.pendingDelete = nil // Cancel the sheet; no store mutation.
        #expect(f.ids == before && f.selectedID == before[1])
        #expect(try f.key())
        let entry = try #require(f.model.library.pendingDelete)
        f.model.library.delete(entry)
        f.model.library.delete(entry) // Duplicate mutation admission is ignored.
        f.model.library.pendingDelete = nil
        try await f.settle()
        #expect(f.ids.count == 2 && f.selectedID == before[2])
    }

    @Test func concurrentRemovalFallsBackWithinOriginalVisibleNeighbors() {
        let anchor = DeletionSelection(deleting: "b", selectedID: "b", visibleIDs: ["a", "b", "c", "d"])
        #expect(anchor?.replacement(in: ["new", "a", "d"]) == "d")
        #expect(anchor?.replacement(in: ["new", "a"]) == "a")
        #expect(anchor?.replacement(in: []) == nil)
        #expect(DeletionSelection(deleting: "b", selectedID: "c", visibleIDs: ["a", "b", "c"]) == nil)
    }
}
