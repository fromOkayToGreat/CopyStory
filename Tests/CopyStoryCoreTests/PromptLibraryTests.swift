import Foundation
import Testing
import CSQLite
@testable import CopyStoryCore

struct PromptTemplateTests {
    @Test func repeatedVariablesEscapesAndLiteralValues() throws {
        let template = try PromptTemplate("  {{topic}}\n{{tone}} / {{topic}} / \\{{literal}} 🧑🏽‍💻\0end")
        #expect(template.variableNames == ["topic", "tone"])
        #expect(try template.render(values: ["topic": "{{not_expanded}}", "tone": "café\n日本語"]) == "  {{not_expanded}}\ncafé\n日本語 / {{not_expanded}} / {{literal}} 🧑🏽‍💻\0end")
    }
    @Test(arguments: ["{{", "{{name}", "{{}}", "{{a b}}", "{{9name}}", "{{é}}", "{{outer{{inner}}}}", "text }}"])
    func malformedSyntaxIsRejected(text: String) {
        #expect(throws: TemplateError.malformedPlaceholder) { try PromptTemplate(text) }
    }
    @Test func identifiersAreCaseSensitiveAndFieldsAreRequired() throws {
        let template = try PromptTemplate("{{a}} {{A}} {{_value2}}")
        #expect(template.variableNames == ["a", "A", "_value2"])
        #expect(throws: TemplateError.missingValue("A")) { try template.render(values: ["a": "x"]) }
        #expect(throws: TemplateError.missingValue("a")) { try template.render(values: ["a": " \n"]) }
    }
    @Test func defaultsDropdownsAndConfigurationValidation() throws {
        var entry = LibraryEntry(title: "Explain", template: "Explain {{topic}} in a {{tone}} tone.", variables: [
            .init(name: "topic", defaultValue: "Photosynthesis"),
            .init(name: "tone", kind: .dropdown, defaultValue: "Friendly", options: ["Friendly", "Concise"])
        ])
        #expect(try entry.render(values: entry.defaultValues) == "Explain Photosynthesis in a Friendly tone.")
        #expect(throws: TemplateError.missingValue("tone")) { try entry.render(values: ["topic": "x", "tone": "Unknown"]) }
        entry.variables[1].options = ["Friendly", "Friendly"]
        #expect(throws: TemplateError.invalidDropdown("tone")) { try entry.validate() }
        entry.variables = []
        #expect(throws: TemplateError.invalidVariables) { try entry.validate() }
    }
    @Test func emptyDefaultsCanBeSavedButNotUsed() throws {
        let entry = LibraryEntry(title: "Prompt", template: "{{value}}", variables: [.init(name: "value")])
        try entry.validate()
        #expect(throws: TemplateError.missingValue("value")) { try entry.render(values: entry.defaultValues) }
        #expect(try LibraryEntry(title: "Snippet", template: "exact\ntext").render(values: [:]) == "exact\ntext")
    }
    @Test func boundsExpandedOutput() throws {
        let template = try PromptTemplate("{{x}}{{x}}")
        let large = String(repeating: "a", count: HistoryStore.maximumTextBytes / 2 + 1)
        #expect(throws: TemplateError.oversized) { try template.render(values: ["x": large]) }
    }
}

@Suite(.serialized)
final class LibraryStoreTests {
    private var folders: [URL] = []
    deinit { for folder in folders { try? FileManager.default.removeItem(at: folder) } }
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CopyStory-LibraryTests-\(UUID().uuidString)")
        folders.append(url); return url
    }
    @Test func mixedTemplateMigrationPreservesBuild26ActiveAndTrashedText() async throws {
        let root = folder()
        let active = LibraryEntry(title: "Active", template: "Hi {{who}}", variables: [.init(name: "who", defaultValue: "Taylor")], isFavorite: true)
        let trashed = LibraryEntry(title: "Trash", template: "Keep me")
        var store: LibraryStore? = try LibraryStore(directory: root)
        try await store!.create(active)
        try await store!.create(trashed)
        let deletedAt = Date(timeIntervalSince1970: 5)
        _ = try await store!.moveToTrash(id: trashed.id, at: deletedAt)
        store = nil
        do {
            let db = try SQLiteDatabase(path: root.appendingPathComponent("library.sqlite").path)
            for table in ["prompts", "trash"] {
                try db.execute("ALTER TABLE \(table) DROP COLUMN images")
            }
            try db.execute("PRAGMA user_version=2")
        }
        let migrated = try LibraryStore(directory: root)
        let saved = try #require(try await migrated.entry(id: active.id))
        #expect(saved.images.isEmpty)
        #expect(saved.isFavorite)
        #expect(try saved.render(values: saved.defaultValues) == "Hi Taylor")
        let trash = try #require(try await migrated.trashItems().first)
        #expect(trash.entry.id == trashed.id)
        #expect(trash.entry.template == trashed.template)
        #expect(trash.entry.images.isEmpty)
        #expect(trash.deletedAt == deletedAt)
        #expect(try await migrated.restoreFromTrash(id: trashed.id))
    }

    @Test func mixedImagesSurviveReopenReorderAndTrash() async throws {
        let root = folder()
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH1sAAAAASUVORK5CYII="))
        let a = try TemplateImage(label: "A / Upload", png: png)
        let b = try TemplateImage(label: "B / Browse", png: png)
        #expect(throws: TemplateError.invalidImages) {
            _ = try TemplateImage(label: "Fake", png: Data("not an image".utf8))
        }
        var value = LibraryEntry(title: "Walkthrough", template: "{{name}}, choose Upload, then Browse.",
                                 variables: [.init(name: "name", defaultValue: "Taylor")], images: [a,b])
        var store: LibraryStore? = try LibraryStore(directory: root)
        try await store!.create(value)
        store = nil
        store = try LibraryStore(directory: root)
        #expect(try await store!.entry(id: value.id)?.images == [a,b])
        value.images.reverse()
        try await store!.update(value)
        _ = try await store!.moveToTrash(id: value.id)
        #expect(try await store!.trashItems().first?.entry.images == [b,a])
        #expect(try await store!.restoreFromTrash(id: value.id))
        let restored = try #require(try await store!.entry(id: value.id))
        #expect(restored.images == [b,a])
        #expect(try restored.render(values: ["name": "Taylor"]) == "Taylor, choose Upload, then Browse.")
        value.images = [a,a]
        #expect(throws: TemplateError.invalidImages) { try value.validate() }
    }

    @Test func CRUDSearchFavoritesAndReopen() async throws {
        let root = folder()
        var store: LibraryStore? = try LibraryStore(directory: root)
        var alpha = LibraryEntry(title: "Alpha", template: "Full text café 日本語\n{{value}}", variables: [.init(name: "value", defaultValue: "original")])
        let beta = LibraryEntry(title: "Beta", template: "Plain snippet", isFavorite: true)
        try await store!.create(alpha); try await store!.create(beta)
        #expect(try await store!.search(query: "").map(\.id) == [beta.id, alpha.id])
        #expect(try await store!.search(query: "CAFE 日本語").map(\.id) == [alpha.id])
        #expect(try await store!.search(query: "", favoritesOnly: true).map(\.id) == [beta.id])
        alpha.variables[0].defaultValue = "changed"
        try await store!.update(alpha)
        try await store!.setFavorite(id: alpha.id, favorite: true)
        store = nil
        let reopened = try LibraryStore(directory: root)
        let saved = try #require(try await reopened.entry(id: alpha.id))
        #expect(saved.defaultValues == ["value": "changed"])
        #expect(saved.isFavorite)
        #expect(abs(saved.createdAt.timeIntervalSince1970 - alpha.createdAt.timeIntervalSince1970) < 0.000001)
        #expect(try await reopened.search(query: "", limit: 1, offset: 1).map(\.id) == [beta.id])
        try await reopened.delete(id: alpha.id)
        #expect(try await reopened.entry(id: alpha.id) == nil)
    }
    @Test func failedUpdatePreservesSavedEntryAndDeletedEntriesStayDeleted() async throws {
        let store = try LibraryStore(directory: folder())
        var entry = LibraryEntry(title: "Keep", template: "original")
        try await store.create(entry)
        entry.template = "{{invalid"
        await #expect(throws: TemplateError.malformedPlaceholder) { try await store.update(entry) }
        #expect(try await store.entry(id: entry.id)?.template == "original")
        entry.template = "valid"
        try await store.delete(id: entry.id)
        await #expect(throws: LibraryStoreError.self) { try await store.update(entry) }
        #expect(try await store.search(query: "").isEmpty)
    }
    @Test func libraryAndHistoryHaveIndependentLifetimesAndBudgets() async throws {
        let root = folder()
        let history = try HistoryStore(directory: root)
        let library = try LibraryStore(directory: root.appendingPathComponent("Library"))
        let limits = HistoryLimits(maxItems: 1, maxBytes: 60_000)
        _ = try await history.capture(CapturePayload(text: "completed"), limits: limits)
        let originalBytes = try await history.stats().totalBytes
        let entry = LibraryEntry(title: "Large permanent prompt", template: String(repeating: "word ", count: 20_000))
        try await library.create(entry)
        #expect(try await history.stats().totalBytes == originalBytes)
        #expect(try await history.enforceLimits(limits) == false)
        #expect(try await history.stats().count == 1)
        try await library.delete(id: entry.id)
        #expect(try await history.stats().count == 1)
        try await library.create(entry)
        try await history.clear(includePinned: true)
        _ = try await history.expireUnpinned(before: Date.distantFuture)
        #expect(try await library.entry(id: entry.id) != nil)
    }
    @Test func ownerPermissionsLockAndSymlinkAdmission() async throws {
        let root = folder()
        let store = try LibraryStore(directory: root)
        _ = try await store.search(query: "")
        #expect(throws: LibraryStoreError.self) { try LibraryStore(directory: root) }
        let permissions = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("library.sqlite").path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        let linked = folder()
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: root)
        #expect(throws: (any Error).self) { try LibraryStore(directory: linked) }
        withExtendedLifetime(store) {}
    }
    @Test(arguments: [false, true]) func corruptOrFutureDatabaseIsNeverReplaced(future: Bool) throws {
        let root = folder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("library.sqlite")
        if future {
            let db = try SQLiteDatabase(path: url.path)
            try db.execute("PRAGMA user_version=99")
        } else { try Data("not a database".utf8).write(to: url) }
        let before = try Data(contentsOf: url)
        #expect(throws: (any Error).self) { try LibraryStore(directory: root) }
        #expect(try Data(contentsOf: url) == before)
    }
}
