import AppKit
import Foundation
import Testing
import CopyStoryCore
@testable import CopyStory

// Exercise the actual native search-field delegate, with disposable stores/defaults.
// Never creates an application/window, starts recording, or reads the clipboard.
@Suite(.serialized) @MainActor
struct SectionSearchTests {
    @Test func exampleDraftUsesExplicitSaveAndIsOnlyAvailableInEmptyTemplates() async throws {
        let f = try Fixture(); defer { f.clean() }
        let library = f.model.library
        let store = try #require(library.store)
        library.section = .library
        #expect(!library.canStartExample)
        await library.refresh()
        #expect(library.canStartExample)

        library.favoritesOnly = true
        await library.refresh()
        #expect(!library.canStartExample)
        library.startExample()
        #expect(library.screen == .browse)
        library.favoritesOnly = false
        library.query = "no matches"
        await library.refresh()
        #expect(!library.canStartExample)
        library.query = ""
        await library.refresh()

        library.startExample()
        let example = try #require(library.draft)
        #expect(library.screen == .editor)
        #expect(example.title == "Friendly follow-up")
        #expect(example.variables.map(\.name) == ["name"])
        #expect(library.draftError == nil)
        #expect(try await store.entry(id: example.id) == nil)
        library.draft?.title = "Changed in editor"
        library.back()
        #expect(library.confirmDiscard)
        library.discardChanges()
        #expect(library.screen == .browse)
        #expect(try await store.entry(id: example.id) == nil)

        library.startExample()
        let toSave = try #require(library.draft)
        #expect(toSave.id != example.id)
        library.saveDraft()
        for _ in 0..<1000 where library.saving {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(!library.saving)
        let saved = try #require(try await store.entry(id: toSave.id))
        #expect(saved.title == "Friendly follow-up")
        library.open(saved)
        library.values["name"] = "Avery"
        #expect(try library.rendered?.get().hasPrefix("Hi Avery,") == true)
        library.back()

        library.open(saved)
        #expect(library.values == saved.defaultValues)
        library.values["name"] = "Jordan"
        #expect(try library.rendered?.get().hasPrefix("Hi Jordan,") == true)
        library.back()
        #expect(try await store.entry(id: toSave.id) == saved)
        #expect(!library.canStartExample)
        #expect(try await f.model.store.stats().count == 0)
    }

    @Test func templatesRenamePreservesSectionAndStorageIdentity() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        #expect(PanelSection.library.rawValue == "Library")
        #expect(PanelSection.library.displayName == "Templates")
        #expect(PanelSection.history.displayName == "History")
        #expect(f.model.library.store?.directory.lastPathComponent == "Library")
        let entry = try #require(f.model.library.items.first)
        let saved = try await f.model.library.store?.entry(id: entry.id)
        #expect(saved?.id == entry.id && saved?.template == entry.template)
        #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Library/library.sqlite").path))
    }

    @Test func historyFiltersSurviveTabSwitchAndResetOnFreshOpen() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.model.dateFilter = .custom
        f.model.dateFrom = Date(timeIntervalSince1970: 0)
        f.model.dateThrough = Date(timeIntervalSince1970: 200)
        f.model.filter = .text
        f.model.query = "even"
        await f.settleBoth()
        let selection = f.model.selectedID
        f.model.selectSection(.library)
        f.model.query = "odd"
        await f.settleBoth()
        f.model.selectSection(.history)
        #expect(f.model.filter == .text && f.model.dateFilter == .custom)
        #expect(f.model.query == "even" && f.model.selectedID == selection)
        f.model.filter = .links
        await f.settleBoth()
        #expect(f.model.items.isEmpty && f.model.selectedID == nil && !f.model.hasMore)
        f.model.clearHistoryFilters()
        await f.settleBoth()
        #expect(f.model.items.count == 7 && f.model.library.query == "odd")
        f.model.dateFilter = .today
        f.model.resetSearchForReopen()
        await f.settleBoth()
        #expect(f.model.dateFilter == .all && f.model.items.count == 7)
    }

    @MainActor final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopyStory-SectionSearch-\(UUID())")
        let suite = "CopyStory.SectionSearch.\(UUID())"
        let defaults: UserDefaults
        let model: AppModel
        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            model = AppModel(store: try HistoryStore(directory: root), demo: true, preferenceStore: defaults)
        }
        func seed() async throws {
            for i in 1...7 {
                let text = "Sample \(i % 2 == 0 ? "even" : "odd") item \(i)"
                _ = try await model.store.capture(CapturePayload(text: text, capturedAt: Date(timeIntervalSince1970: Double(100-i))), limits: .init())
                try await model.library.store!.create(LibraryEntry(title: text, template: text))
            }
            await model.refresh(); await model.library.refresh()
        }
        func typeThroughField(_ query: String) {
            let field = NSTextField()
            field.stringValue = query
            let coordinator = HistorySearchField(model: model).makeCoordinator()
            coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        }
        func settleBoth() async { await model.refresh(); await model.library.refresh() }
        func clean() {
            _ = model.prepareForTermination(); model.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test func libraryNativeSearchAndClearMustNotMoveHiddenHistorySelection() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        let before = f.model.items.map(\.id)
        let selected = try #require(f.model.items.first { $0.preview.contains("item 7") })
        f.model.selectedID = selected.id
        f.model.selectSection(.library)
        f.typeThroughField("even")
        await f.settleBoth()
        #expect(f.model.library.query == "even")
        #expect(f.model.library.items.count == 3)
        #expect(f.model.items.map(\.id) == before)
        #expect(f.model.selectedID == selected.id)
        f.typeThroughField("")
        await f.settleBoth()
        f.model.selectSection(.history)
        #expect(f.model.query.isEmpty)
        #expect(f.model.selectedID == selected.id)
    }
    @Test func eachTabDisplaysItsOwnQueryAndMatchingResults() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.model.selectSection(.library)
        f.typeThroughField("odd")
        await f.settleBoth()
        let libraryIDs = f.model.library.items.map(\.id)
        let librarySelection = f.model.library.items.last!.id
        f.model.library.selectedID = librarySelection
        f.model.selectSection(.history)
        f.typeThroughField("even")
        await f.settleBoth()
        #expect(f.model.query == "even" && f.model.historyQuery == "even")
        #expect(f.model.items.count == 3 && f.model.items.allSatisfy { $0.preview.contains("even") })
        #expect(f.model.library.items.map(\.id) == libraryIDs)
        #expect(f.model.library.selectedID == librarySelection)
        let historySelection = f.model.selectedID
        f.model.selectSection(.library)
        #expect(f.model.query == "odd" && f.model.library.items.count == 4)
        f.model.query = "" // The visible Clear button uses this same UI property.
        await f.settleBoth()
        #expect(f.model.query.isEmpty && f.model.library.items.count == 7)
        #expect(f.model.selectedID == historySelection && f.model.items.count == 3)
        f.model.selectSection(.history)
        #expect(f.model.query == "even")
        f.typeThroughField("even") // Unchanged native-field notifications remain inert.
        #expect(!f.model.isSearching && !f.model.library.searching)
    }

    @Test func rapidTabSwitchesDoNotMixPendingSearchResults() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.typeThroughField("odd")
        f.typeThroughField("even")
        f.model.selectSection(.library)
        f.typeThroughField("even")
        f.typeThroughField("odd")
        await f.settleBoth()
        #expect(f.model.historyQuery == "even" && f.model.library.query == "odd")
        #expect(f.model.items.count == 3 && f.model.items.allSatisfy { $0.preview.contains("even") })
        #expect(f.model.library.items.count == 4 && f.model.library.items.allSatisfy { $0.title.contains("odd") })
        for _ in 0..<3 {
            f.model.selectSection(.history); #expect(f.model.query == "even")
            f.model.selectSection(.library); #expect(f.model.query == "odd")
        }
    }

    @Test func notificationsFromDetachedTabFieldsAreIgnored() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        f.typeThroughField("odd")
        let oldHistoryField = HistorySearchField(model: f.model).makeCoordinator()
        f.model.selectSection(.library)
        f.typeThroughField("even")
        let late = NSTextField(); late.stringValue = "stale event"
        oldHistoryField.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: late))
        await f.settleBoth()
        #expect(f.model.historyQuery == "odd" && f.model.query == "even")
        #expect(f.model.items.count == 4 && f.model.library.items.count == 3)
    }

    @Test func freshReopenClearsBothQueriesWithoutLosingSurvivingSelections() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        let historySelection = try #require(f.model.items.last?.id)
        f.model.selectedID = historySelection
        f.model.selectSection(.library)
        f.typeThroughField("even")
        await f.settleBoth()
        let librarySelection = f.model.library.selectedID
        f.model.resetSearchForReopen() // Same entry used by the normal AppDelegate.
        await f.settleBoth()
        #expect(f.model.library.section == .history && f.model.filter == .all)
        #expect(f.model.query.isEmpty && f.model.historyQuery.isEmpty && f.model.library.query.isEmpty)
        #expect(f.model.items.count == 7 && f.model.library.items.count == 7)
        #expect(f.model.selectedID == historySelection)
        #expect(f.model.library.selectedID == librarySelection)
    }

    @Test func deletionThroughVisibleLibrarySearchKeepsNeighborAndHiddenHistory() async throws {
        let f = try Fixture(); defer { f.clean() }; try await f.seed()
        let historySelection = try #require(f.model.items.last?.id)
        f.model.selectedID = historySelection
        f.model.selectSection(.library)
        f.typeThroughField("even")
        await f.settleBoth()
        let visible = f.model.library.items
        try #require(visible.count == 3)
        f.model.library.selectedID = visible[1].id
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51))
        #expect(f.model.library.handleDeletionKey(event, responder: NSView()))
        #expect(f.model.library.pendingDelete?.id == visible[1].id)
        f.model.library.delete(visible[1]); f.model.library.pendingDelete = nil
        await f.model.library.waitForPendingWrites()
        #expect(f.model.query == "even" && f.model.library.items.count == 2)
        #expect(f.model.library.selectedID == visible[2].id)
        #expect(f.model.selectedID == historySelection && f.model.items.count == 7)
    }

}
