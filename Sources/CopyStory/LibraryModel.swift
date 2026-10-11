import Foundation
import SwiftUI
import CopyStoryCore

enum PanelSection: String, CaseIterable { case history = "History", library = "Library" }
enum LibraryScreen { case browse, editor, use }

@MainActor
final class LibraryModel: ObservableObject {
    let store: LibraryStore?
    @Published var section: PanelSection = .history
    @Published private(set) var screen: LibraryScreen = .browse
    @Published var items: [LibraryEntry] = []
    @Published var selectedID: String?
    @Published var favoritesOnly = false { didSet { scheduleSearch() } }
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published private(set) var searching = false
    @Published private(set) var hasMore = false
    @Published var draft: LibraryEntry?
    @Published private(set) var useEntry: LibraryEntry?
    @Published var values: [String: String] = [:]
    @Published var errorMessage: String?
    @Published private(set) var saving = false
    @Published var confirmDiscard = false
    @Published var pendingDelete: LibraryEntry?
    private var originalDraft: LibraryEntry?
    private var editingExisting = false
    private var searchTask: Task<Void, Never>?
    private var revision = 0
    private var pageLimit = 100
    private var mutation: Task<Void, Never>?
    private var terminating = false
    private var discardAction: (() -> Void)?

    init(directory: URL) {
        do { store = try LibraryStore(directory: directory) }
        catch { store = nil; errorMessage = "The prompt library is unavailable. Your history is still available. \(error is LibraryStoreError ? error.localizedDescription : "Check local storage and permissions.")" }
    }

    var selected: LibraryEntry? { items.first { $0.id == selectedID } }
    var isDirty: Bool { screen == .editor && draft != originalDraft }
    var draftError: String? {
        guard let draft else { return nil }
        do { try draft.validate(); return nil } catch { return error.localizedDescription }
    }
    var rendered: Result<String, Error>? { useEntry.map { entry in Result { try entry.render(values: values) } } }

    func scheduleSearch() {
        guard !terminating, store != nil else { return }
        revision += 1; pageLimit = 100; searching = true
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
    func refresh() async {
        guard let store else { return }
        let version = revision, q = query, favorites = favoritesOnly, limit = pageLimit
        do {
            var rows: [LibraryEntry] = []
            while rows.count < limit + 1 {
                let size = min(1000, limit + 1 - rows.count)
                let batch = try await store.search(query: q, favoritesOnly: favorites, limit: size, offset: rows.count)
                rows += batch
                if batch.count < size { break }
            }
            guard version == revision, !terminating else { return }
            items = Array(rows.prefix(limit)); hasMore = rows.count > limit; searching = false
            if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
        } catch {
            guard version == revision, !terminating else { return }
            searching = false; items = []; selectedID = nil
            errorMessage = "The prompt library could not be read. Existing saved prompts have not been replaced."
        }
    }
    func loadMore() { pageLimit += 100; Task { await refresh() } }
    func moveSelection(_ delta: Int) {
        guard !items.isEmpty, !searching else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? 0
        let next = max(0, min(items.count - 1, index + delta))
        selectedID = items[next].id
        if next >= items.count - 3 && hasMore { loadMore() }
    }

    func edit(_ entry: LibraryEntry? = nil, text: String? = nil) {
        guard store != nil, !saving, !terminating, entry == nil || !searching else { return }
        var value = entry ?? LibraryEntry(template: text ?? "")
        if entry == nil, let text {
            value.title = String(text.split(whereSeparator: { $0.isNewline }).first?.prefix(80) ?? "")
            value.variables = ((try? PromptTemplate(text).variableNames) ?? []).map { TemplateVariable(name: $0) }
        }
        editingExisting = entry != nil
        draft = value; originalDraft = value; screen = .editor; section = .library; errorMessage = nil
    }
    func setTemplate(_ text: String) {
        guard var value = draft else { return }
        value.template = text
        if let names = try? PromptTemplate(text).variableNames {
            value.variables = names.map { name in value.variables.first { $0.name == name } ?? TemplateVariable(name: name) }
        }
        draft = value
    }
    func open(_ entry: LibraryEntry) {
        guard !searching, !saving, !terminating else { return }
        section = .library; useEntry = entry; values = entry.defaultValues; screen = .use; errorMessage = nil
    }
    func back() { requestDismiss { [weak self] in self?.resetScreen() } }
    func resetScreen() {
        screen = .browse; draft = nil; originalDraft = nil; useEntry = nil; values = [:]
    }
    func requestDismiss(_ action: @escaping () -> Void) {
        guard !saving else { return }
        if isDirty { discardAction = action; confirmDiscard = true }
        else { action() }
    }
    func discardChanges() {
        let action = discardAction; discardAction = nil; confirmDiscard = false
        resetScreen(); action?()
    }
    func cancelDiscard() { discardAction = nil; confirmDiscard = false }

    func saveDraft() {
        guard let entry = draft, let store, !saving, !terminating else { return }
        do { try entry.validate() } catch { errorMessage = error.localizedDescription; return }
        let update = editingExisting
        saving = true; errorMessage = nil
        enqueue { [self] in
            defer { saving = false }
            do {
                if update { try await store.update(entry) } else { try await store.create(entry) }
                resetScreen(); revision += 1
                await refresh()
                selectedID = items.first(where: { $0.id == entry.id })?.id ?? selectedID
            } catch { errorMessage = "Couldn’t save this prompt. Your draft is still here. \(error is TemplateError ? error.localizedDescription : "Check local storage and permissions.")" }
        }
    }
    func toggleFavorite(_ entry: LibraryEntry) {
        guard let store, !terminating else { return }
        enqueue { [self] in
            do {
                guard let current = try await store.entry(id: entry.id) else { throw LibraryStoreError.missingEntry }
                try await store.setFavorite(id: entry.id, favorite: !current.isFavorite)
                revision += 1; await refresh()
            }
            catch { errorMessage = "Couldn’t update this favorite." }
        }
    }
    func delete(_ entry: LibraryEntry) {
        guard let store, !terminating else { return }
        enqueue { [self] in
            do { try await store.delete(id: entry.id); revision += 1; await refresh() }
            catch { errorMessage = "Couldn’t delete this prompt." }
        }
    }
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = mutation
        mutation = Task { await previous?.value; await operation() }
    }
    func waitForPendingWrites() async { await mutation?.value }

    func prepareForTermination() -> Task<Void, Never> {
        terminating = true; searchTask?.cancel()
        let pending = mutation
        return Task { await pending?.value }
    }
}
