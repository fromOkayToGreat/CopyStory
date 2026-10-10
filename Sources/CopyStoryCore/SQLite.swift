import Foundation
import CSQLite

enum SQLValue {
    case text(String), integer(Int64), real(Double), null
    static func optional(_ value: String?) -> SQLValue { value.map(SQLValue.text) ?? .null }
    static func optional(_ value: Int?) -> SQLValue { value.map { .integer(Int64($0)) } ?? .null }
}

final class SQLiteDatabase {
    private var handle: OpaquePointer?
    init(path: String) throws {
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else { if let handle { sqlite3_close(handle) }; handle = nil; throw HistoryStoreError.database(result) }
        sqlite3_busy_timeout(handle, 2_000)
    }
    deinit { sqlite3_close(handle) }
    func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else { throw HistoryStoreError.database(status) }
    }
    func rows<T>(_ sql: String, _ values: [SQLValue] = [], map: (OpaquePointer) throws -> T) throws -> [T] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw HistoryStoreError.database(status) }
            result.append(try map(statement))
        }
    }
    func scalar(_ sql: String, _ values: [SQLValue] = []) throws -> Int64 {
        try rows(sql, values) { sqlite3_column_int64($0, 0) }.first ?? 0
    }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else { throw HistoryStoreError.database(status) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let parameter = Int32(index + 1)
            let result: Int32
            switch value {
            case .integer(let integer): result = sqlite3_bind_int64(statement, parameter, integer)
            case .real(let real): result = sqlite3_bind_double(statement, parameter, real)
            case .null: result = sqlite3_bind_null(statement, parameter)
            case .text(let text):
                result = text.utf8CString.withUnsafeBufferPointer { bytes in
                    sqlite3_bind_text(statement, parameter, bytes.baseAddress, Int32(bytes.count - 1), transient)
                }
            }
            if result != SQLITE_OK { sqlite3_finalize(statement); throw HistoryStoreError.database(result) }
        }
        return statement
    }
}

func sqlString(_ statement: OpaquePointer, _ column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL,
          let bytes = sqlite3_column_text(statement, column) else { return nil }
    let count = Int(sqlite3_column_bytes(statement, column))
    return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
}
func sqlInt(_ statement: OpaquePointer, _ column: Int32) -> Int? {
    sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
}
