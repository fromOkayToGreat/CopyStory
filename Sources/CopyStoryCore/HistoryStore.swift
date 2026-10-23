import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import CSQLite
import Darwin

/// All database and filesystem operations run on this actor, off the UI actor.
public actor HistoryStore {
    public static let maximumTextBytes = 32_000_000
    public static let maximumImageBytes = 100_000_000
    public static let maximumImagePixels = 32_000_000
    private let engine: StoreEngine
    public nonisolated let directory: URL
    public init(directory: URL, reportInitializationFailure: ((StartupFailure) -> Void)? = nil) throws {
        try self.init(directory: directory, initialization: HistoryInitializationDiagnostics(reportFailure: reportInitializationFailure))
    }
    // Internal fault seam for inert tests; ordinary callers cannot inject stages.
    init(directory: URL, initialization: HistoryInitializationDiagnostics) throws {
        do { engine = try StoreEngine(directory: directory, initialization: initialization) }
        catch {
            initialization.reportFailure?(StartupFailure(stage: initialization.stage, error: error))
            throw error
        }
        self.directory = directory.standardizedFileURL
    }
    public func capture(_ payload: CapturePayload, limits: HistoryLimits) throws -> StoreOutcome { try engine.capture(payload, limits: limits) }
    public func search(query: String, filter: HistoryFilter, limit: Int = 100, offset: Int = 0) throws -> [HistoryItem] { try engine.search(query: query, filter: filter, limit: limit, offset: offset) }
    public func stats() throws -> HistoryStats { try engine.stats() }
    public func item(id: String) throws -> HistoryItem? { try engine.item(id: id) }
    public func payload(id: String) throws -> CapturePayload { try engine.payload(id: id) }
    public func thumbnailURL(id: String) throws -> URL? { try engine.thumbnailURL(id: id) }
    public func setPinned(id: String, pinned: Bool) throws { try engine.setPinned(id: id, pinned: pinned) }
    public func delete(id: String) throws { try engine.delete(id: id) }
    public func clear(includePinned: Bool) throws { try engine.clear(includePinned: includePinned) }
    public func expireUnpinned(before cutoff: Date) throws -> Int { try engine.expireUnpinned(before: cutoff) }
    public func enforceLimits(_ limits: HistoryLimits) throws -> Bool { try engine.enforceLimits(limits) }
    public func fullText(id: String) throws -> String? { try engine.fullText(id: id) }
}

final class HistoryInitializationDiagnostics {
    private(set) var stage: StartupStage = .historyDirectory
    let reportFailure: ((StartupFailure) -> Void)?
    private let beforeStage: ((StartupStage) throws -> Void)?
    init(reportFailure: ((StartupFailure) -> Void)? = nil, beforeStage: ((StartupStage) throws -> Void)? = nil) {
        self.reportFailure = reportFailure
        self.beforeStage = beforeStage
    }
    func enter(_ stage: StartupStage) throws {
        self.stage = stage
        try beforeStage?(stage)
    }
}

private final class StoreEngine {
    private let directory: URL
    private let images: URL
    private let databaseURL: URL
    private let db: SQLiteDatabase
    private let lockFD: Int32
    private let fm = FileManager.default
    private static let columns = "id, kind, preview, source_app, source_bundle, captured_at, pinned, byte_count, width, height, (text_content IS NOT NULL AND length(CAST(text_content AS BLOB)) > 0)"
    private static let schema = """
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('text','image')),
            text_content TEXT,
            search_content TEXT NOT NULL,
            preview TEXT NOT NULL,
            source_app TEXT,
            source_bundle TEXT,
            captured_at REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0 CHECK(pinned IN (0,1)),
            byte_count INTEGER NOT NULL CHECK(byte_count >= 0),
            file_bytes INTEGER NOT NULL CHECK(file_bytes >= 0),
            width INTEGER,
            height INTEGER,
            content_hash TEXT NOT NULL UNIQUE
        )
        """

    init(directory: URL, initialization: HistoryInitializationDiagnostics) throws {
        try initialization.enter(.historyDirectory)
        guard directory.isFileURL, directory.path.hasPrefix("/"), directory.path != "/" else { throw HistoryStoreError.invalidDirectory }
        self.directory = directory.standardizedFileURL
        images = self.directory.appendingPathComponent("Images", isDirectory: true)
        databaseURL = self.directory.appendingPathComponent("history.sqlite")
        try StoreFiles.prepareDirectory(self.directory)
        try initialization.enter(.historyImagesDirectory)
        try StoreFiles.prepareDirectory(images)
        let lockURL = self.directory.appendingPathComponent(".store-lock")
        try initialization.enter(.historyLockValidation)
        if fm.fileExists(atPath: lockURL.path) { _ = try StoreFiles.regularFileSize(lockURL) }
        try initialization.enter(.historyLockOpen)
        lockFD = Darwin.open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw HistoryStoreError.storageUnavailable }
        // Keep all throwing diagnostics after open inside lock cleanup below.
        do { try initialization.enter(.historyLockAcquire) }
        catch { Darwin.close(lockFD); throw error }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lockFD); throw HistoryStoreError.alreadyOpen }
        do {
            try initialization.enter(.historyFileAdmission)
            for path in [databaseURL, URL(fileURLWithPath: databaseURL.path + "-journal"), URL(fileURLWithPath: databaseURL.path + "-wal"), URL(fileURLWithPath: databaseURL.path + "-shm")] {
                if StoreFiles.exists(path) { _ = try StoreFiles.regularFileSize(path); try StoreFiles.ownerOnly(path) }
            }
            try initialization.enter(.historyDatabaseOpen)
            db = try SQLiteDatabase(path: databaseURL.path)
            try initialization.enter(.historyConfiguration)
            try Self.configure(db)
            try initialization.enter(.historyDatabasePermissions)
            try StoreFiles.ownerOnly(databaseURL)
            try initialization.enter(.historyIntegrityCheck)
            let check = try db.rows("PRAGMA quick_check") { sqlString($0, 0) }
            guard check.count == 1, check[0] == "ok" else { throw HistoryStoreError.database(SQLITE_CORRUPT) }
            try initialization.enter(.historySchema)
            try Self.initializeSchema(db)
            try recover(initialization: initialization)
        } catch {
            flock(lockFD, LOCK_UN); Darwin.close(lockFD)
            throw error
        }
    }
    deinit { flock(lockFD, LOCK_UN); Darwin.close(lockFD) }

    private static func configure(_ db: SQLiteDatabase) throws {
        try db.execute("PRAGMA journal_mode=DELETE")
        try db.execute("PRAGMA synchronous=FULL")
        try db.execute("PRAGMA auto_vacuum=FULL")
        // Clear deleted SQL content during normal writes; this is not secure erasure.
        try db.execute("PRAGMA secure_delete=ON")
        try db.execute("PRAGMA temp_store=MEMORY")
        try db.execute("PRAGMA trusted_schema=OFF")
    }
    private static func initializeSchema(_ db: SQLiteDatabase) throws {
        let version = try db.scalar("PRAGMA user_version")
        guard version <= 1 else { throw HistoryStoreError.unsupportedSchema }
        try db.transaction {
            try db.execute(schema)
            try db.execute("CREATE INDEX IF NOT EXISTS items_recency ON items(captured_at DESC, id DESC)")
            try db.execute("PRAGMA user_version=1")
        }
    }

    func capture(_ input: CapturePayload, limits: HistoryLimits) throws -> StoreOutcome {
        try validate(limits)
        guard input.capturedAt.timeIntervalSince1970.isFinite else { throw HistoryStoreError.emptyPayload }
        if (input.text?.utf8.count ?? 0) > HistoryStore.maximumTextBytes ||
            (input.imageData?.count ?? 0) > HistoryStore.maximumImageBytes { return .oversized }
        var payload = input
        payload.sourceApp = input.sourceApp.map { String($0.prefix(256)) }
        payload.sourceBundleID = input.sourceBundleID.map { String($0.prefix(256)) }
        if payload.text == "" { payload.text = nil }
        guard payload.text != nil || payload.imageData != nil else { throw HistoryStoreError.emptyPayload }
        if let data = payload.imageData {
            guard Int64(data.count) <= limits.maxBytes else { return .oversized }
            let details = try Self.imageDetails(data: data)
            payload.pixelWidth = details.width; payload.pixelHeight = details.height
            // Generate our own bounded thumbnail; callers' thumbnails are untrusted.
            payload.thumbnailData = details.thumbnail
        } else {
            payload.thumbnailData = nil; payload.pixelWidth = nil; payload.pixelHeight = nil
        }
        let hash = Self.contentHash(payload)
        let id = UUID().uuidString.lowercased()
        let fields = values(id: id, payload: payload, hash: hash)
        let fileBytes = Int64((payload.imageData?.count ?? 0) + (payload.thumbnailData?.count ?? 0))
        // A real database with the same schema gives a conservative single-item
        // footprint, including indexes and duplicated search text, before eviction.
        let probe = try SQLiteDatabase(path: ":memory:")
        try Self.configure(probe); try Self.initializeSchema(probe)
        try insert(into: probe, fields: fields)
        let singleItemBytes = try databaseBytes(probe) + fileBytes
        guard singleItemBytes <= limits.maxBytes else { return .oversized }

        if let duplicateID = try db.rows("SELECT id FROM items WHERE content_hash = ?", [.text(hash)], map: { sqlString($0, 0) }).first ?? nil {
            // A repeated copy has new provenance and recency, while identity,
            // content and pin state survive. Metadata growth also obeys limits.
            var evicted: [String] = []
            do {
                try db.transaction {
                    try db.execute("UPDATE items SET source_app = ?, source_bundle = ?, captured_at = ?, search_content = ?, byte_count = ? WHERE id = ?", [
                        fields[5], fields[6], fields[7], fields[3], fields[8], .text(duplicateID)])
                    evicted = try prune(limits, protecting: duplicateID)
                    if try exceeds(limits) { throw CapacityBlocked.blocked }
                }
            } catch CapacityBlocked.blocked {
                return .pinnedCapacity
            }
            for oldID in evicted { try removeFiles(id: oldID) }
            return .duplicate
        }

        var evicted: [String] = []
        do {
            if let data = payload.imageData { try write(data, to: fileURL(id: id, thumbnail: false)) }
            if let data = payload.thumbnailData { try write(data, to: fileURL(id: id, thumbnail: true)) }
            do {
                try db.transaction {
                    try insert(into: db, fields: fields)
                    evicted = try prune(limits, protecting: id)
                    if try exceeds(limits) { throw CapacityBlocked.blocked }
                }
            } catch CapacityBlocked.blocked {
                try removeFiles(id: id)
                return .pinnedCapacity
            }
        } catch {
            try? removeFiles(id: id)
            throw error
        }
        for oldID in evicted { try removeFiles(id: oldID) }
        try StoreFiles.ownerOnly(databaseURL)
        return .saved
    }

    private enum CapacityBlocked: Error { case blocked }

    private func values(id: String, payload: CapturePayload, hash: String) -> [SQLValue] {
        let kind: HistoryKind = payload.imageData == nil ? .text : .image
        let fileBytes = Int64((payload.imageData?.count ?? 0) + (payload.thumbnailData?.count ?? 0))
        let byteCount = fileBytes + Int64((payload.text?.utf8.count ?? 0) + (payload.sourceApp?.utf8.count ?? 0) + (payload.sourceBundleID?.utf8.count ?? 0))
        let preview = payload.text.map { String($0.prefix(240)) } ?? "Image"
        return [.text(id), .text(kind.rawValue), .optional(payload.text),
                .text(Self.searchable(text: payload.text, app: payload.sourceApp, date: payload.capturedAt)),
                .text(preview), .optional(payload.sourceApp), .optional(payload.sourceBundleID),
                .real(payload.capturedAt.timeIntervalSince1970), .integer(byteCount), .integer(fileBytes),
                .optional(payload.pixelWidth), .optional(payload.pixelHeight), .text(hash)]
    }
    private func insert(into database: SQLiteDatabase, fields: [SQLValue]) throws {
        try database.execute("""
            INSERT INTO items(id,kind,text_content,search_content,preview,source_app,source_bundle,
                              captured_at,byte_count,file_bytes,width,height,content_hash)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, fields)
    }

    func search(query: String, filter: HistoryFilter, limit: Int, offset: Int) throws -> [HistoryItem] {
        var conditions: [String] = []
        var values: [SQLValue] = []
        switch filter {
        case .all: break
        case .text: conditions.append("kind = 'text'")
        case .images: conditions.append("kind = 'image'")
        case .pinned: conditions.append("pinned = 1")
        }
        // Bound pathological search inputs while preserving ordinary partial-term search.
        let terms = Self.fold(String(query.prefix(2_048))).split(whereSeparator: { $0.isWhitespace }).prefix(32)
        for term in terms { conditions.append("instr(search_content, ?) > 0"); values.append(.text(String(term))) }
        let clause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        values.append(.integer(Int64(max(0, min(limit, 1_000)))))
        values.append(.integer(Int64(max(0, offset))))
        return try db.rows("SELECT \(Self.columns) FROM items\(clause) ORDER BY captured_at DESC, id DESC LIMIT ? OFFSET ?", values, map: Self.readItem)
    }
    func item(id: String) throws -> HistoryItem? {
        try validateID(id)
        return try db.rows("SELECT \(Self.columns) FROM items WHERE id = ?", [.text(id)], map: Self.readItem).first
    }
    func fullText(id: String) throws -> String? {
        try validateID(id)
        return try db.rows("SELECT text_content FROM items WHERE id = ?", [.text(id)]) { sqlString($0, 0) }.first ?? nil
    }
    func payload(id: String) throws -> CapturePayload {
        guard let item = try item(id: id) else { throw HistoryStoreError.missingItem }
        var imageData: Data?
        if item.kind == .image {
            do {
                imageData = try read(fileURL(id: id, thumbnail: false), maximum: HistoryStore.maximumImageBytes)
                guard let imageData else { throw HistoryStoreError.damagedImage }
                _ = try Self.imageDetails(data: imageData)
            } catch {
                try delete(id: id)
                throw HistoryStoreError.damagedImage
            }
        }
        return CapturePayload(text: try fullText(id: id), imageData: imageData,
                              pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight,
                              sourceApp: item.sourceApp, sourceBundleID: item.sourceBundleID, capturedAt: item.capturedAt)
    }
    func thumbnailURL(id: String) throws -> URL? {
        guard let item = try item(id: id), item.kind == .image else { return nil }
        let url = try fileURL(id: id, thumbnail: true)
        guard StoreFiles.exists(url) else { return nil }
        do {
            let data = try read(url, maximum: 1_000_000)
            guard Self.isValidThumbnail(data) else { return nil }
            return url
        }
        catch { return nil }
    }
    func setPinned(id: String, pinned: Bool) throws {
        try validateID(id)
        try db.transaction { try db.execute("UPDATE items SET pinned = ? WHERE id = ?", [.integer(pinned ? 1 : 0), .text(id)]) }
    }
    func delete(id: String) throws {
        try validateID(id)
        try db.transaction { try db.execute("DELETE FROM items WHERE id = ?", [.text(id)]) }
        try removeFiles(id: id)
    }
    func clear(includePinned: Bool) throws {
        let condition = includePinned ? "" : " WHERE pinned = 0"
        let ids = try db.rows("SELECT id FROM items" + condition) { sqlString($0, 0) ?? "" }
        try db.transaction { try db.execute("DELETE FROM items" + condition) }
        for id in ids { try removeFiles(id: id) }
    }
    func enforceLimits(_ limits: HistoryLimits) throws -> Bool {
        try validate(limits)
        var removed: [String] = []
        let blocked = try db.transaction {
            removed = try prune(limits, protecting: nil)
            return try exceeds(limits)
        }
        for id in removed { try removeFiles(id: id) }
        return blocked
    }
    func expireUnpinned(before cutoff: Date) throws -> Int {
        let timestamp = cutoff.timeIntervalSince1970
        guard timestamp.isFinite else { throw HistoryStoreError.invalidLimits }
        let ids = try db.rows("SELECT id FROM items WHERE pinned = 0 AND captured_at < ?", [.real(timestamp)]) { sqlString($0, 0) ?? "" }
        try db.transaction {
            try db.execute("DELETE FROM items WHERE pinned = 0 AND captured_at < ?", [.real(timestamp)])
        }
        for id in ids { try removeFiles(id: id) }
        return ids.count
    }
    func stats() throws -> HistoryStats {
        let count = Int(try db.scalar("SELECT COUNT(*) FROM items"))
        let pinned = Int(try db.scalar("SELECT COUNT(*) FROM items WHERE pinned = 1"))
        let pinnedFiles = try db.scalar("SELECT COALESCE(SUM(file_bytes),0) FROM items WHERE pinned = 1")
        let dbBytes = try StoreFiles.regularFileSize(databaseURL)
        let files = try imageDirectoryBytes()
        let pinnedShare = count == 0 ? 0 : Int64((Double(dbBytes) * Double(pinned) / Double(count)).rounded(.up))
        return HistoryStats(count: count, pinnedCount: pinned, totalBytes: dbBytes + files, pinnedBytes: pinnedFiles + pinnedShare)
    }

    private func prune(_ limits: HistoryLimits, protecting protectedID: String?) throws -> [String] {
        guard try exceeds(limits) else { return [] }
        let candidates = try db.rows("SELECT id FROM items WHERE pinned = 0 AND id != ? ORDER BY captured_at ASC, id ASC", [.text(protectedID ?? "")]) { sqlString($0, 0) ?? "" }
        var removed: [String] = []
        for id in candidates {
            if try !exceeds(limits) { break }
            try db.execute("DELETE FROM items WHERE id = ?", [.text(id)])
            removed.append(id)
        }
        return removed
    }
    private func exceeds(_ limits: HistoryLimits) throws -> Bool {
        let count = try db.scalar("SELECT COUNT(*) FROM items")
        let files = try db.scalar("SELECT COALESCE(SUM(file_bytes),0) FROM items")
        let bytes = try databaseBytes(db) + files
        return count > Int64(limits.maxItems) || bytes > limits.maxBytes
    }
    private func databaseBytes(_ database: SQLiteDatabase) throws -> Int64 {
        let pages = try database.scalar("PRAGMA page_count")
        let free = try database.scalar("PRAGMA freelist_count")
        let size = try database.scalar("PRAGMA page_size")
        // FULL auto-vacuum returns free pages to the filesystem at COMMIT.
        return max(0, pages - free) * size
    }
    private func imageDirectoryBytes() throws -> Int64 {
        var sum: Int64 = 0
        for url in try fm.contentsOfDirectory(at: images, includingPropertiesForKeys: nil) {
            sum += try StoreFiles.regularFileSize(url)
        }
        return sum
    }

    private static func readItem(_ row: OpaquePointer) throws -> HistoryItem {
        guard let id = sqlString(row, 0), UUID(uuidString: id) != nil,
              let kind = HistoryKind(rawValue: sqlString(row, 1) ?? ""),
              let preview = sqlString(row, 2) else { throw HistoryStoreError.database(SQLITE_CORRUPT) }
        return HistoryItem(id: id, kind: kind, preview: preview, hasText: sqlite3_column_int(row, 10) != 0, sourceApp: sqlString(row, 3),
                           sourceBundleID: sqlString(row, 4), capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 5)),
                           isPinned: sqlite3_column_int(row, 6) != 0, byteCount: sqlite3_column_int64(row, 7),
                           pixelWidth: sqlInt(row, 8), pixelHeight: sqlInt(row, 9))
    }
    private static func fold(_ string: String) -> String {
        string.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func searchable(text: String?, app: String?, date: Date) -> String {
        let iso = ISO8601DateFormatter().string(from: date)
        let local = DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .short)
        return fold([text, app, iso, local].compactMap { $0 }.joined(separator: "\n"))
    }
    private static func contentHash(_ payload: CapturePayload) -> String {
        var digest = SHA256()
        digest.update(data: Data((payload.imageData == nil ? "text\n" : "image\n").utf8))
        if let text = payload.text { digest.update(data: Data("\(text.utf8.count):".utf8)); digest.update(data: Data(text.utf8)) }
        else { digest.update(data: Data("nil:".utf8)) }
        if let image = payload.imageData { digest.update(data: image) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func imageDetails(data: Data) throws -> (width: Int, height: Int, thumbnail: Data) {
        guard !data.isEmpty, data.count <= HistoryStore.maximumImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= 16_384, height <= 16_384,
              width <= HistoryStore.maximumImagePixels / height,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceShouldCacheImmediately: false
              ] as CFDictionary) else { throw HistoryStoreError.damagedImage }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { throw HistoryStoreError.damagedImage }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination), bytes.length <= 1_000_000 else { throw HistoryStoreError.damagedImage }
        return (width, height, bytes as Data)
    }

    private static func isValidThumbnail(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete, CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return false }
        return width > 0 && width <= 320 && height > 0 && height <= 320
    }

    private func recover(initialization: HistoryInitializationDiagnostics) throws {
        // Files are written before metadata commits; deletions happen after commits.
        // Reconciliation removes either kind of orphan after an interrupted write.
        try initialization.enter(.historyRecoveryQuery)
        let rows = try db.rows("SELECT id,kind FROM items") { (sqlString($0, 0) ?? "", sqlString($0, 1) ?? "") }
        try initialization.enter(.historyRecoveryImages)
        var referenced = Set<String>()
        var invalid: [String] = []
        for (id, kind) in rows {
            guard UUID(uuidString: id) != nil, id == id.lowercased(), HistoryKind(rawValue: kind) != nil else { invalid.append(id); continue }
            guard kind == HistoryKind.image.rawValue else { continue }
            let full = try fileURL(id: id, thumbnail: false)
            let thumb = try fileURL(id: id, thumbnail: true)
            do {
                let data = try read(full, maximum: HistoryStore.maximumImageBytes)
                let details = try Self.imageDetails(data: data)
                // Recreate corrupt or absent thumbnails from the preserved image.
                let thumbValid: Bool
                if let bytes = try? read(thumb, maximum: 1_000_000) {
                    thumbValid = Self.isValidThumbnail(bytes)
                } else { thumbValid = false }
                if !thumbValid { try write(details.thumbnail, to: thumb) }
                let thumbBytes = try StoreFiles.regularFileSize(thumb)
                try StoreFiles.ownerOnly(full); try StoreFiles.ownerOnly(thumb)
                let fileBytes = Int64(data.count) + thumbBytes
                try db.execute("UPDATE items SET byte_count = byte_count - file_bytes + ?, file_bytes = ?, width = ?, height = ? WHERE id = ?", [
                    .integer(fileBytes), .integer(fileBytes), .integer(Int64(details.width)), .integer(Int64(details.height)), .text(id)])
                referenced.insert(full.lastPathComponent); referenced.insert(thumb.lastPathComponent)
            } catch { invalid.append(id) }
        }
        try initialization.enter(.historyRecoveryTransaction)
        try db.transaction {
            for id in invalid { try db.execute("DELETE FROM items WHERE id = ?", [.text(id)]) }
        }
        try initialization.enter(.historyRecoveryEnumeration)
        let imageFiles = try fm.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)
        try initialization.enter(.historyRecoveryOrphanRemoval)
        for url in imageFiles where !referenced.contains(url.lastPathComponent) {
            // Unlinking a symlink removes the link itself and never follows its target.
            var info = Darwin.stat()
            guard lstat(url.path, &info) == 0 else { continue }
            guard (info.st_mode & S_IFMT) != S_IFDIR else { throw HistoryStoreError.unsafeFile }
            guard unlink(url.path) == 0 else { throw HistoryStoreError.storageUnavailable }
        }
    }

    private func validate(_ limits: HistoryLimits) throws {
        guard limits.maxItems > 0, limits.maxBytes > 0 else { throw HistoryStoreError.invalidLimits }
    }
    private func validateID(_ id: String) throws {
        guard UUID(uuidString: id) != nil, id == id.lowercased() else { throw HistoryStoreError.unsafeFile }
    }
    private func fileURL(id: String, thumbnail: Bool) throws -> URL {
        try validateID(id)
        return images.appendingPathComponent(id + (thumbnail ? ".thumb.png" : ".image"))
    }
    private func write(_ data: Data, to url: URL) throws {
        if StoreFiles.exists(url) { _ = try StoreFiles.regularFileSize(url) }
        do { try data.write(to: url, options: .atomic); try StoreFiles.ownerOnly(url) }
        catch { throw HistoryStoreError.storageUnavailable }
    }
    private func read(_ url: URL, maximum: Int) throws -> Data {
        let size = try StoreFiles.regularFileSize(url)
        guard size > 0, size <= Int64(maximum) else { throw HistoryStoreError.damagedImage }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    private func removeFiles(id: String) throws {
        for thumbnail in [false, true] {
            let url = try fileURL(id: id, thumbnail: thumbnail)
            if StoreFiles.exists(url) {
                // unlink is also safe when a damaged record has been replaced by a symlink.
                guard unlink(url.path) == 0 else { throw HistoryStoreError.storageUnavailable }
            }
        }
    }
}
