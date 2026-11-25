import Foundation
import CSQLite
import Darwin

public enum LibraryStoreError: LocalizedError {
    case missingEntry, unavailable, unsupportedSchema
    public var errorDescription: String? {
        switch self {
        case .missingEntry: return "This saved template is no longer available."
        case .unavailable: return "Templates could not be read or saved. Check local storage and permissions."
        case .unsupportedSchema: return "These templates were created by a newer version of CopyStory."
        }
    }
}

public struct LibraryTrashItem: Sendable, Identifiable {
    public let entry: LibraryEntry
    public let deletedAt: Date
    public var id: String { entry.id }
}

public actor LibraryStore {
    public nonisolated let directory: URL
    private let engine: LibraryEngine
    /// Pass the Library subdirectory, never the history store's root.
    public init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        engine = try LibraryEngine(directory: self.directory)
    }
    public func create(_ entry: LibraryEntry) throws { try engine.save(entry, create: true) }
    public func update(_ entry: LibraryEntry) throws { try engine.save(entry, create: false) }
    public func entry(id: String) throws -> LibraryEntry? { try engine.entry(id: id) }
    public func search(query: String, favoritesOnly: Bool = false, limit: Int = 100, offset: Int = 0) throws -> [LibraryEntry] {
        try engine.search(query: query, favoritesOnly: favoritesOnly, limit: limit, offset: offset)
    }
    public func setFavorite(id: String, favorite: Bool) throws { try engine.setFavorite(id: id, favorite: favorite) }
    public func delete(id: String) throws { try engine.delete(id: id) }
    @discardableResult public func moveToTrash(id: String, at date: Date = Date()) throws -> LibraryTrashItem { try engine.moveToTrash(id: id, at: date) }
    public func trashItems(limit: Int = 1000, offset: Int = 0) throws -> [LibraryTrashItem] { try engine.trashItems(limit: limit, offset: offset) }
    public func trashCount() throws -> Int { try engine.trashCount() }
    public func restoreFromTrash(id: String) throws -> Bool { try engine.restoreFromTrash(id: id) }
    public func deleteFromTrash(id: String) throws { try engine.deleteFromTrash(id: id) }
    public func emptyTrash() throws { _ = try engine.purgeTrash(before: nil) }
    @discardableResult public func purgeTrash(before date: Date) throws -> Int { try engine.purgeTrash(before: date) }
}

private final class LibraryEngine {
    private let db: SQLiteDatabase
    private let lockFD: Int32
    private static let storedColumns = "id,title,template,variables,favorite,created_at,modified_at,search_content,sort_title,images"
    private static let columns = "id,title,template,variables,favorite,created_at,modified_at,images"

    init(directory: URL) throws {
        guard directory.isFileURL, directory.path.hasPrefix("/"), directory.path != "/" else { throw LibraryStoreError.unavailable }
        try StoreFiles.prepareDirectory(directory)
        let lock = directory.appendingPathComponent(".store-lock")
        if StoreFiles.exists(lock) { _ = try StoreFiles.regularFileSize(lock) }
        lockFD = Darwin.open(lock.path, O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw LibraryStoreError.unavailable }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lockFD); throw LibraryStoreError.unavailable }
        do {
            let path = directory.appendingPathComponent("library.sqlite").path
            for suffix in ["", "-journal", "-wal", "-shm"] {
                let url = URL(fileURLWithPath: path + suffix)
                if StoreFiles.exists(url) { try StoreFiles.ownerOnly(url) }
            }
            db = try SQLiteDatabase(path: path)
            try StoreFiles.ownerOnly(URL(fileURLWithPath: path))
            for pragma in ["journal_mode=DELETE", "synchronous=FULL", "auto_vacuum=FULL", "secure_delete=ON", "temp_store=MEMORY", "trusted_schema=OFF"] {
                try db.execute("PRAGMA " + pragma)
            }
            let check = try db.rows("PRAGMA quick_check") { sqlString($0, 0) }
            guard check == ["ok"] else { throw LibraryStoreError.unavailable }
            let version = try db.scalar("PRAGMA user_version")
            guard version <= 3 else { throw LibraryStoreError.unsupportedSchema }
            try db.transaction {
                try db.execute("""
                    CREATE TABLE IF NOT EXISTS prompts (
                        id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, template TEXT NOT NULL,
                        variables TEXT NOT NULL, favorite INTEGER NOT NULL CHECK(favorite IN (0,1)),
                        created_at REAL NOT NULL, modified_at REAL NOT NULL,
                        search_content TEXT NOT NULL, sort_title TEXT NOT NULL
                    )
                    """)
                try db.execute("CREATE INDEX IF NOT EXISTS prompts_order ON prompts(favorite DESC,sort_title,id)")
                try db.execute("""
                    CREATE TABLE IF NOT EXISTS trash (
                        id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, template TEXT NOT NULL,
                        variables TEXT NOT NULL, favorite INTEGER NOT NULL CHECK(favorite IN (0,1)),
                        created_at REAL NOT NULL, modified_at REAL NOT NULL,
                        search_content TEXT NOT NULL, sort_title TEXT NOT NULL, deleted_at REAL NOT NULL
                    )
                    """)
                try db.execute("CREATE INDEX IF NOT EXISTS trash_deletion ON trash(deleted_at DESC,id DESC)")
                if version < 3 {
                    for table in ["prompts", "trash"] {
                        try db.execute("ALTER TABLE \(table) ADD COLUMN images TEXT NOT NULL DEFAULT '[]'")
                    }
                }
                try db.execute("PRAGMA user_version=3")
            }
        } catch {
            flock(lockFD, LOCK_UN); Darwin.close(lockFD); throw error
        }
    }
    deinit { flock(lockFD, LOCK_UN); Darwin.close(lockFD) }

    func save(_ input: LibraryEntry, create: Bool) throws {
        try input.validate()
        guard UUID(uuidString: input.id) != nil, input.createdAt.timeIntervalSince1970.isFinite else { throw LibraryStoreError.unavailable }
        let variables = String(decoding: try JSONEncoder().encode(input.variables), as: UTF8.self)
        guard variables.utf8.count + input.title.utf8.count + input.template.utf8.count <= HistoryStore.maximumTextBytes else { throw TemplateError.oversized }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let images = String(decoding: try encoder.encode(input.images), as: UTF8.self)
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let values: [SQLValue] = [.text(title), .text(input.template), .text(variables), .integer(input.isFavorite ? 1 : 0),
                                  .real(Date().timeIntervalSince1970), .text(Self.fold(title + "\n" + input.template)), .text(Self.fold(title)), .text(images)]
        try db.transaction {
            if create {
                try db.execute("INSERT INTO prompts(title,template,variables,favorite,modified_at,search_content,sort_title,images,id,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)",
                               values + [.text(input.id), .real(input.createdAt.timeIntervalSince1970)])
            } else {
                guard try entry(id: input.id) != nil else { throw LibraryStoreError.missingEntry }
                try db.execute("UPDATE prompts SET title=?,template=?,variables=?,favorite=?,modified_at=?,search_content=?,sort_title=?,images=? WHERE id=?", values + [.text(input.id)])
            }
        }
    }

    func entry(id: String) throws -> LibraryEntry? {
        try db.rows("SELECT \(Self.columns) FROM prompts WHERE id=?", [.text(id)], map: Self.read).first
    }
    func search(query: String, favoritesOnly: Bool, limit: Int, offset: Int) throws -> [LibraryEntry] {
        var conditions = favoritesOnly ? ["favorite=1"] : [], values: [SQLValue] = []
        for term in Self.fold(String(query.prefix(2048))).split(whereSeparator: { $0.isWhitespace }).prefix(32) {
            conditions.append("instr(search_content,?)>0"); values.append(.text(String(term)))
        }
        let clause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        values += [.integer(Int64(max(0, min(limit, 1000)))), .integer(Int64(max(0, offset)))]
        return try db.rows("SELECT \(Self.columns) FROM prompts\(clause) ORDER BY favorite DESC,sort_title,id LIMIT ? OFFSET ?", values, map: Self.read)
    }
    func setFavorite(id: String, favorite: Bool) throws {
        try db.transaction {
            guard try entry(id: id) != nil else { throw LibraryStoreError.missingEntry }
            try db.execute("UPDATE prompts SET favorite=?,modified_at=? WHERE id=?", [.integer(favorite ? 1 : 0), .real(Date().timeIntervalSince1970), .text(id)])
        }
    }
    func delete(id: String) throws {
        try db.transaction { try db.execute("DELETE FROM prompts WHERE id=?", [.text(id)]) }
    }
    @discardableResult
    func moveToTrash(id: String, at date: Date) throws -> LibraryTrashItem {
        guard date.timeIntervalSince1970.isFinite else { throw LibraryStoreError.unavailable }
        guard let value = try entry(id: id) else { throw LibraryStoreError.missingEntry }
        try db.transaction {
            try db.execute("INSERT INTO trash(\(Self.storedColumns),deleted_at) SELECT \(Self.storedColumns),? FROM prompts WHERE id=?", [.real(date.timeIntervalSince1970),.text(id)])
            try db.execute("DELETE FROM prompts WHERE id=?", [.text(id)])
        }
        return LibraryTrashItem(entry: value, deletedAt: date)
    }
    func trashItems(limit: Int, offset: Int) throws -> [LibraryTrashItem] {
        try db.rows("SELECT \(Self.columns),deleted_at FROM trash ORDER BY deleted_at DESC,id DESC LIMIT ? OFFSET ?",
            [.integer(Int64(max(0,min(limit,1000)))),.integer(Int64(max(0,offset)))]) { row in
            let date = sqlite3_column_double(row,8)
            guard date.isFinite else { throw LibraryStoreError.unavailable }
            return LibraryTrashItem(entry: try Self.read(row), deletedAt: Date(timeIntervalSince1970: date))
        }
    }
    func trashCount() throws -> Int { Int(try db.scalar("SELECT COUNT(*) FROM trash")) }
    func restoreFromTrash(id: String) throws -> Bool {
        if try entry(id: id) != nil { return false }
        guard try !db.rows("SELECT id FROM trash WHERE id=?", [.text(id)], map: { sqlString($0,0) }).isEmpty else { throw LibraryStoreError.missingEntry }
        try db.transaction {
            try db.execute("INSERT INTO prompts(\(Self.storedColumns)) SELECT \(Self.storedColumns) FROM trash WHERE id=?", [.text(id)])
            try db.execute("DELETE FROM trash WHERE id=?", [.text(id)])
        }
        return true
    }
    func deleteFromTrash(id: String) throws {
        try db.transaction { try db.execute("DELETE FROM trash WHERE id=?", [.text(id)]) }
    }
    @discardableResult
    func purgeTrash(before date: Date?) throws -> Int {
        if let date, !date.timeIntervalSince1970.isFinite { throw LibraryStoreError.unavailable }
        let condition = date == nil ? "" : " WHERE deleted_at <= ?"
        let values: [SQLValue] = date.map { [.real($0.timeIntervalSince1970)] } ?? []
        return try db.transaction {
            let count = Int(try db.scalar("SELECT COUNT(*) FROM trash" + condition, values))
            try db.execute("DELETE FROM trash" + condition, values)
            return count
        }
    }
    private static func read(_ row: OpaquePointer) throws -> LibraryEntry {
        guard let id = sqlString(row, 0), UUID(uuidString: id) != nil,
              let title = sqlString(row, 1), let template = sqlString(row, 2), let json = sqlString(row, 3),
              let variables = try? JSONDecoder().decode([TemplateVariable].self, from: Data(json.utf8)),
              let imageJSON = sqlString(row, 7), imageJSON.utf8.count <= 6 * 1024 * 1024,
              let images = try? JSONDecoder().decode([TemplateImage].self, from: Data(imageJSON.utf8)) else { throw LibraryStoreError.unavailable }
        let entry = LibraryEntry(id: id, title: title, template: template, variables: variables, images: images,
                                 isFavorite: sqlite3_column_int(row, 4) != 0,
                                 createdAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 5)),
                                 modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 6)))
        try entry.validate()
        return entry
    }
    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
