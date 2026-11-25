import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CopyStoryCore

@Suite(.serialized)
final class TrashStoreTests {
    private var roots: [URL] = []
    deinit { for root in roots { try? FileManager.default.removeItem(at: root) } }
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("copystory-trash-tests-" + UUID().uuidString)
        roots.append(url); return url
    }
    private func image() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination)); return data as Data
    }
    private func add(_ text: String, _ store: HistoryStore, image: Data? = nil) async throws -> String {
        _ = try await store.capture(.init(text: text, imageData: image, sourceApp: "Synthetic", sourceBundleID: "test.synthetic", capturedAt: Date(timeIntervalSince1970: 123)), limits: .init())
        return try #require(await store.search(query: text, filter: .all).first?.id)
    }

    @Test func historyTrashSurvivesReopenAndRestoresIdentityImageAndPin() async throws {
        let path = folder(), bytes = try image()
        var store: HistoryStore? = try HistoryStore(directory: path)
        let id = try await add("Synthetic image", store!, image: bytes)
        try await store!.setPinned(id: id, pinned: true)
        let original = try #require(await store!.item(id: id))
        let deletion = try await store!.moveToTrash(id: id, at: Date(timeIntervalSince1970: 400))
        #expect(deletion.item == original && deletion.deletedAt.timeIntervalSince1970 == 400)
        #expect(try await store!.search(query: "", filter: .all).isEmpty)
        #expect(try await store!.fullText(id: id) == nil)
        do { _ = try await store!.payload(id: id); Issue.record("Trash cannot be pasted") } catch HistoryStoreError.missingItem { }
        // A stale permanent-delete call must not remove a trash image.
        try await store!.delete(id: id)
        store = nil
        let reopened = try HistoryStore(directory: path)
        #expect(try await reopened.trashCount() == 1)
        #expect(try await reopened.trashItems().first?.item == original)
        #expect(try await reopened.restoreFromTrash(id: id, limits: .init()) == .restored)
        #expect(try await reopened.item(id: id) == original)
        #expect(try await reopened.payload(id: id).imageData == bytes)
        #expect(try await reopened.trashCount() == 0)
        #expect(try await reopened.restoreFromTrash(id: id, limits: .init()) == .alreadyPresent)
    }

    @Test func historyRestoreBlockedDoesNotEvictAndDuplicateIsKept() async throws {
        let store = try HistoryStore(directory: folder())
        let old = try await add("old", store)
        try await store.moveToTrash(id: old)
        let current = try await add("current", store)
        #expect(try await store.restoreFromTrash(id: old, limits: .init(maxItems: 1)) == .capacityBlocked)
        #expect(try await store.trashCount() == 1)
        #expect(try await store.search(query: "", filter: .all).map(\.id) == [current])
        let newerDuplicate = try await add("old", store)
        #expect(newerDuplicate != old)
        #expect(try await store.restoreFromTrash(id: old, limits: .init()) == .alreadyPresent)
        #expect(try await store.trashCount() == 1)
        #expect(try await store.item(id: newerDuplicate) != nil)
    }

    @Test func historyPurgeBoundaryAndClearPrivacyScope() async throws {
        let store = try HistoryStore(directory: folder())
        let first = try await add("first", store, image: image())
        let second = try await add("second", store)
        try await store.setPinned(id: second, pinned: true)
        try await store.moveToTrash(id: first, at: Date(timeIntervalSince1970: 10))
        try await store.moveToTrash(id: second, at: Date(timeIntervalSince1970: 20))
        #expect(try await store.trashItems(limit: 1).map(\.id) == [second])
        #expect(try await store.trashItems(limit: 1, offset: 1).map(\.id) == [first])
        #expect(try await store.purgeTrash(before: Date(timeIntervalSince1970: 9)) == 0)
        #expect(try await store.purgeTrash(before: Date(timeIntervalSince1970: 10)) == 1)
        #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("Images/\(first).image").path))
        try await store.clear(includePinned: false)
        #expect(try await store.trashCount() == 1)
        try await store.clear(includePinned: true)
        #expect(try await store.trashCount() == 0)
        do { _ = try await store.restoreFromTrash(id: second, limits: .init()); Issue.record("Purged trash cannot return") } catch HistoryStoreError.missingItem { }
    }

    @Test func historyMoveAndPurgeRejectInvalidDatesWithoutMutation() async throws {
        let store = try HistoryStore(directory: folder())
        let id = try await add("keep", store)
        do { try await store.moveToTrash(id: id, at: Date(timeIntervalSince1970: .nan)); Issue.record("Expected finite date") } catch HistoryStoreError.invalidLimits { }
        #expect(try await store.item(id: id) != nil)
        try await store.moveToTrash(id: id)
        do { try await store.purgeTrash(before: Date(timeIntervalSince1970: .infinity)); Issue.record("Expected finite cutoff") } catch HistoryStoreError.invalidLimits { }
        #expect(try await store.trashCount() == 1)
    }

    @Test func templatesRestoreExactFavoriteVariablesAndDatesAfterReopen() async throws {
        let path = folder()
        var store: LibraryStore? = try LibraryStore(directory: path)
        let entry = LibraryEntry(title: "Synthetic greeting", template: "Hi {{name}}", variables: [.init(name: "name", defaultValue: "Friend")], isFavorite: true)
        try await store!.create(entry)
        let original = try #require(await store!.entry(id: entry.id))
        try await store!.moveToTrash(id: entry.id, at: Date(timeIntervalSince1970: 400))
        #expect(try await store!.search(query: "").isEmpty)
        store = nil
        let reopened = try LibraryStore(directory: path)
        #expect(try await reopened.trashItems().first?.entry == original)
        #expect(try await reopened.restoreFromTrash(id: entry.id))
        #expect(try await reopened.entry(id: entry.id) == original)
        #expect(try await reopened.trashCount() == 0)
        #expect(try await !reopened.restoreFromTrash(id: entry.id))
    }

    @Test func templateDuplicateNeverOverwritesAndCleanupIsBounded() async throws {
        let store = try LibraryStore(directory: folder())
        var entry = LibraryEntry(title: "Original", template: "original")
        try await store.create(entry)
        try await store.moveToTrash(id: entry.id, at: Date(timeIntervalSince1970: 10))
        entry.title = "Newer"; entry.template = "newer"
        try await store.create(entry)
        #expect(try await !store.restoreFromTrash(id: entry.id))
        #expect(try await store.entry(id: entry.id)?.title == "Newer")
        #expect(try await store.purgeTrash(before: Date(timeIntervalSince1970: 9)) == 0)
        #expect(try await store.purgeTrash(before: Date(timeIntervalSince1970: 10)) == 1)
        #expect(try await store.entry(id: entry.id) != nil)
        try await store.moveToTrash(id: entry.id)
        try await store.emptyTrash()
        #expect(try await store.trashCount() == 0)
    }

    @Test func versionOneMigrationPreservesActiveDataAndFutureVersionFailsClosed() async throws {
        let path = folder()
        var store: HistoryStore? = try HistoryStore(directory: path)
        let id = try await add("migration", store!)
        store = nil
        do {
            let db = try SQLiteDatabase(path: path.appendingPathComponent("history.sqlite").path)
            try db.execute("DROP TABLE trash"); try db.execute("PRAGMA user_version=1")
        }
        store = try HistoryStore(directory: path)
        #expect(try await store!.item(id: id) != nil)
        try await store!.moveToTrash(id: id)
        store = nil
        do {
            let db = try SQLiteDatabase(path: path.appendingPathComponent("history.sqlite").path)
            #expect(try db.scalar("PRAGMA user_version") == 2)
            try db.execute("PRAGMA user_version=3")
        }
        do { _ = try HistoryStore(directory: path); Issue.record("Expected unsupported version") } catch HistoryStoreError.unsupportedSchema { }
        let db = try SQLiteDatabase(path: path.appendingPathComponent("history.sqlite").path)
        #expect(try db.scalar("SELECT COUNT(*) FROM trash") == 1)
        #expect(try db.scalar("PRAGMA user_version") == 3)
    }

    @Test func failedMigrationRollsBackAndPreservesVersionOneRows() async throws {
        let path = folder()
        var store: HistoryStore? = try HistoryStore(directory: path)
        let id = try await add("keep during failed migration", store!)
        store = nil
        do {
            let db = try SQLiteDatabase(path: path.appendingPathComponent("history.sqlite").path)
            try db.execute("DROP TABLE trash")
            // Conflicting v1 object forces CREATE TABLE failure mid-migration.
            try db.execute("CREATE VIEW trash AS SELECT id FROM items")
            try db.execute("PRAGMA user_version=1")
        }
        do { _ = try HistoryStore(directory: path); Issue.record("Expected failed migration") } catch { }
        let db = try SQLiteDatabase(path: path.appendingPathComponent("history.sqlite").path)
        #expect(try db.scalar("PRAGMA user_version") == 1)
        #expect(try db.rows("SELECT id FROM items", map: { sqlString($0,0) }).compactMap { $0 } == [id])
    }
    @Test func trashBytesDoNotEvictActiveHistoryOrPreventSmallCapture() async throws {
        let store = try HistoryStore(directory: folder())
        let big = String(repeating: "synthetic large deleted text ", count: 30_000)
        let id = try await add(big, store)
        try await store.moveToTrash(id: id)
        let limit = HistoryLimits(maxItems: 2, maxBytes: 200_000)
        #expect(try await !store.enforceLimits(limit))
        #expect(try await store.capture(.init(text: "small active"), limits: limit) == .saved)
        #expect(try await store.trashCount() == 1)
        #expect(try await store.search(query: "", filter: .all).map(\.preview) == ["small active"])
        #expect(try await store.restoreFromTrash(id: id, limits: limit) == .capacityBlocked)
        #expect(try await store.trashCount() == 1)
        #expect(try await store.stats().totalBytes > limit.maxBytes)
    }

    @Test func templateMigrationAndInvalidDatesPreserveData() async throws {
        let path = folder()
        var store: LibraryStore? = try LibraryStore(directory: path)
        let value = LibraryEntry(title: "Migration fixture", template: "Keep me")
        try await store!.create(value)
        store = nil
        do {
            let db = try SQLiteDatabase(path: path.appendingPathComponent("library.sqlite").path)
            try db.execute("DROP TABLE trash"); try db.execute("ALTER TABLE prompts DROP COLUMN images"); try db.execute("PRAGMA user_version=1")
        }
        store = try LibraryStore(directory: path)
        #expect(try await store!.entry(id: value.id) != nil)
        do { try await store!.moveToTrash(id: value.id, at: Date(timeIntervalSince1970: .infinity)); Issue.record("Expected finite date") } catch LibraryStoreError.unavailable { }
        #expect(try await store!.entry(id: value.id) != nil)
        try await store!.moveToTrash(id: value.id)
        do { try await store!.purgeTrash(before: Date(timeIntervalSince1970: .nan)); Issue.record("Expected finite cutoff") } catch LibraryStoreError.unavailable { }
        #expect(try await store!.trashCount() == 1)
        store = nil
        let db = try SQLiteDatabase(path: path.appendingPathComponent("library.sqlite").path)
        #expect(try db.scalar("PRAGMA user_version") == 3)
    }

    @Test func legacyUndoCannotRecreateExpiredImage() async throws {
        let path = folder()
        let store = try HistoryStore(directory: path)
        let id = try await add("Expiring image", store, image: image())
        let recovery = try await store.deleteRecoverably(id: id)
        #expect(try await store.expireUnpinned(before: Date(timeIntervalSince1970: 124)) == 1)
        do {
            _ = try await store.restore(recovery, limits: .init())
            Issue.record("Expired recovery must be unavailable")
        } catch HistoryStoreError.missingItem {}
        #expect(try FileManager.default.contentsOfDirectory(atPath: path.appendingPathComponent("Images").path).isEmpty)
    }

    @Test func legacyUndoDelegatesToPersistentTrashWithoutSharedImageRows() async throws {
        let store = try HistoryStore(directory: folder()), bytes = try image()
        let id = try await add("Legacy image recovery", store, image: bytes)
        let recovery = try await store.deleteRecoverably(id: id)
        #expect(try await store.restore(recovery, limits: .init()) == .restored)
        try await store.moveToTrash(id: id)
        try await store.delete(id: id) // Stale active-delete must not unlink Trash.
        #expect(try await store.trashCount() == 1)
        #expect(try await store.restore(recovery, limits: .init()) == .restored)
        #expect(try await store.trashCount() == 0)
        try await store.emptyTrash()
        #expect(try await store.payload(id: id).imageData == bytes)
    }

}
