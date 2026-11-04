import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// A thin wrapper over the system SQLite C API. Only what `StrapStore` needs.
final class SQLiteConnection {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw StoreError.sqlite(message)
        }
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw lastError() }
        return Statement(stmt: stmt, connection: self)
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Runs `PRAGMA wal_checkpoint(mode)` and returns the frames still in the
    /// WAL that were not copied into the main file.
    func checkpoint(_ mode: String) throws -> Int {
        let stmt = try prepare("PRAGMA wal_checkpoint(\(mode))")
        guard try stmt.step() else { return 0 }
        let logFrames = stmt.int(1)
        let checkpointed = stmt.int(2)
        return max(0, logFrames - checkpointed)
    }

    fileprivate func lastError() -> StoreError {
        .sqlite(String(cString: sqlite3_errmsg(handle)))
    }
}

final class Statement {
    private let stmt: OpaquePointer
    private let connection: SQLiteConnection

    fileprivate init(stmt: OpaquePointer, connection: SQLiteConnection) {
        self.stmt = stmt
        self.connection = connection
    }

    deinit { sqlite3_finalize(stmt) }

    func bind(_ values: [Int64]) {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        for (index, value) in values.enumerated() {
            sqlite3_bind_int64(stmt, Int32(index + 1), value)
        }
    }

    func bind(_ values: [Int64?]) {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        for (index, value) in values.enumerated() {
            let column = Int32(index + 1)
            if let value {
                sqlite3_bind_int64(stmt, column, value)
            } else {
                sqlite3_bind_null(stmt, column)
            }
        }
    }

    /// Returns true while a row is available; false when done.
    @discardableResult
    func step() throws -> Bool {
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw connection.lastError()
        }
    }

    func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(stmt, column)) }

    func intOrNil(_ column: Int32) -> Int? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, column))
    }
}

public enum StoreError: Error, Equatable {
    case sqlite(String)
}
